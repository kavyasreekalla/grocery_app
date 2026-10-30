import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'language_provider.dart';
import 'app_strings.dart';

// Models are tried in this order. If one has been retired, or its daily free
// quota is used up, the chat moves on to the next one automatically (each
// model has its own quota). Update this list when model names change.
const List<String> kChatModelNames = [
  'gemini-3.5-flash',
  'gemini-3.7-flash',
  'gemini-3.1-flash-lite',
];

// The orange "Details" and "Voice" notes are hidden normally. To see them
// while testing, build with:  --dart-define=SHOW_DEBUG=true
const bool kShowErrorDetails = bool.fromEnvironment('SHOW_DEBUG');

// After the user finishes speaking, send the message automatically.
const bool kAutoSendVoice = true;

/// One item in the chat list. Order cards also carry a snapshot of the cart.
class _ChatMessage {
  _ChatMessage({
    required this.text,
    required this.isUser,
    this.items,
    this.total,
    this.isDebug = false,
  });

  final String text;
  final bool isUser;
  final bool isDebug;

  // Only set for order confirmation cards.
  final List<Map<String, dynamic>>? items;
  final int? total;

  // For order cards: 'pending', 'confirmed', 'cancelled' or 'outdated'.
  String status = 'pending';

  bool get isOrderCard => items != null;
}

class ChatScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cartItems;
  const ChatScreen({super.key, required this.cartItems});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final List<_ChatMessage> _messages = [];

  // Our own copy of the cart. It is handed back to the home screen on exit.
  late List<Map<String, dynamic>> cartItems;

  // Products from Firestore, keyed by lowercase name.
  final Map<String, Map<String, dynamic>> _productsByName = {};

  ChatSession? _chat;
  String _systemPrompt = '';
  int _modelIndex = 0;

  bool _loading = true;
  bool _initFailed = false;
  String _initError = '';
  bool _isSending = false;
  bool _placingOrder = false;
  bool _isListening = false;
  String? _lastLocaleTried;

  // Small built-in texts so the chat works in all three app languages.
  static const Map<String, Map<String, String>> _strings = {
    'title': {
      'en': 'Mitra',
      'te': 'మిత్రా',
      'hi': 'मित्रा',
    },
    'welcome': {
      'en':
          'Hi! Mitra here, your shopping friend. Ask me about our products, tell me what to add to your cart, or ask me to place your order. Tap the microphone to speak.',
      'te':
          'నమస్కారం! నేను మిత్రా, మీ షాపింగ్ స్నేహితుడిని. మా ఉత్పత్తుల గురించి అడగండి, కార్ట్‌కి ఏమి జోడించాలో చెప్పండి, లేదా ఆర్డర్ చేయమని చెప్పండి. మాట్లాడటానికి మైక్రోఫోన్ నొక్కండి.',
      'hi':
          'नमस्ते! मैं मित्रा हूँ, आपका शॉपिंग दोस्त। हमारे उत्पादों के बारे में पूछें, कार्ट में क्या जोड़ना है बताएं, या ऑर्डर देने के लिए कहें। बोलने के लिए माइक्रोफोन दबाएं।',
    },
    'hint': {
      'en': 'Type or tap the mic…',
      'te': 'టైప్ చేయండి లేదా మైక్ నొక్కండి…',
      'hi': 'लिखें या माइक दबाएं…',
    },
    'listening': {
      'en': 'Listening…',
      'te': 'వింటున్నాను…',
      'hi': 'सुन रहा हूँ…',
    },
    'micDenied': {
      'en': 'Microphone permission is needed to use your voice.',
      'te': 'మీ వాయిస్ ఉపయోగించడానికి మైక్రోఫోన్ అనుమతి అవసరం.',
      'hi': 'आवाज़ का उपयोग करने के लिए माइक्रोफोन की अनुमति चाहिए।',
    },
    'micUnavailable': {
      'en': 'Voice input is not available on this phone.',
      'te': 'ఈ ఫోన్‌లో వాయిస్ ఇన్‌పుట్ అందుబాటులో లేదు.',
      'hi': 'इस फोन पर वॉइस इनपुट उपलब्ध नहीं है।',
    },
    'added': {
      'en': 'Added to cart',
      'te': 'కార్ట్‌కి జోడించబడింది',
      'hi': 'कार्ट में जोड़ा गया',
    },
    'notFound': {
      'en': 'Not found in our products',
      'te': 'మా ఉత్పత్తులలో దొరకలేదు',
      'hi': 'हमारे उत्पादों में नहीं मिला',
    },
    'emptyCart': {
      'en': 'Your cart is empty.',
      'te': 'మీ కార్ట్ ఖాళీగా ఉంది.',
      'hi': 'आपका कार्ट खाली है।',
    },
    'yourOrder': {
      'en': 'Your order',
      'te': 'మీ ఆర్డర్',
      'hi': 'आपका ऑर्डर',
    },
    'cancel': {
      'en': 'Cancel',
      'te': 'రద్దు చేయి',
      'hi': 'रद्द करें',
    },
    'cancelled': {
      'en': 'Order cancelled.',
      'te': 'ఆర్డర్ రద్దు చేయబడింది.',
      'hi': 'ऑर्डर रद्द किया गया।',
    },
    'cartChanged': {
      'en': 'Your cart changed. Ask me to place the order again.',
      'te': 'మీ కార్ట్ మారింది. మళ్లీ ఆర్డర్ చేయమని చెప్పండి.',
      'hi': 'आपका कार्ट बदल गया है। कृपया फिर से ऑर्डर देने के लिए कहें।',
    },
    'orderFailed': {
      'en': 'Could not place the order. Please try again.',
      'te': 'ఆర్డర్ చేయలేకపోయాము. దయచేసి మళ్లీ ప్రయత్నించండి.',
      'hi': 'ऑर्डर नहीं हो सका। कृपया फिर से कोशिश करें।',
    },
    'signIn': {
      'en': 'Please log in to place an order.',
      'te': 'ఆర్డర్ చేయడానికి దయచేసి లాగిన్ అవ్వండి.',
      'hi': 'ऑर्डर देने के लिए कृपया लॉग इन करें।',
    },
    'error': {
      'en': 'The assistant is not available right now. Please try again.',
      'te': 'సహాయకుడు ప్రస్తుతం అందుబాటులో లేడు. దయచేసి మళ్లీ ప్రయత్నించండి.',
      'hi': 'सहायक अभी उपलब्ध नहीं है। कृपया फिर से कोशिश करें।',
    },
    'retry': {
      'en': 'Try again',
      'te': 'మళ్లీ ప్రయత్నించండి',
      'hi': 'फिर से कोशिश करें',
    },
  };

  String _t(String lang, String key) =>
      _strings[key]?[lang] ?? _strings[key]?['en'] ?? key;

  String _languageName(String lang) {
    switch (lang) {
      case 'te':
        return 'Telugu';
      case 'hi':
        return 'Hindi';
      default:
        return 'English';
    }
  }

  String _localeFor(String lang) {
    switch (lang) {
      case 'te':
        return 'te_IN';
      case 'hi':
        return 'hi_IN';
      default:
        return 'en_IN';
    }
  }

  String _shorten(Object error) {
    final text = error.toString();
    return text.length > 400 ? '${text.substring(0, 400)}…' : text;
  }

  @override
  void initState() {
    super.initState();
    cartItems =
        widget.cartItems.map((item) => Map<String, dynamic>.from(item)).toList();
    _init();
  }

  @override
  void dispose() {
    _speech.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Setup: load the product catalog, then create the Gemini chat session.
  // ---------------------------------------------------------------------------

  void _retryInit() {
    setState(() {
      _loading = true;
      _initFailed = false;
    });
    _init();
  }

  Future<void> _init() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('products').get();

      _productsByName.clear();
      final lines = <String>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        _productsByName.putIfAbsent(name.toLowerCase(), () => data);
        lines.add(
          '- $name | brand: ${data['brand'] ?? ''} | '
          '₹${data['price'] ?? '?'} per ${data['unit'] ?? 'unit'} | '
          'category: ${data['category'] ?? ''}',
        );
      }

      _systemPrompt = _buildSystemPrompt(lines.join('\n'));
      _modelIndex = 0;
      _chat = _createChat(kChatModelNames[_modelIndex]);

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Chat init error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initFailed = true;
        _initError = _shorten(e);
      });
    }
  }

  ChatSession _createChat(String modelName) {
    final model = FirebaseAI.googleAI().generativeModel(
      model: modelName,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: _replySchema(),
      ),
    );
    return model.startChat();
  }

  String _buildSystemPrompt(String catalog) {
    return '''
You are Mitra, the friendly shopping assistant inside the VoiceCart grocery app. Your name is written Mitra in English, మిత్రా in Telugu and मित्रा in Hindi. If anyone asks your name or who you are, say you are Mitra, and when you reply in Telugu or Hindi write your name in that language's script. Many users are elderly or new to smartphones, so keep every reply short, warm and simple (1 to 3 short sentences).

LANGUAGE: Reply in the language the user writes in (English, Telugu or Hindi). Use native script for Telugu and Hindi. If the message is unclear, use the app language given at the top of the message.

CATALOG (these are the only products that exist):
$catalog

RULES:
- Only talk about groceries, the products above and the user's cart. Politely decline anything else.
- Never invent products, prices or stock. If something is not in the catalog, say it is not available and suggest a similar catalog item if there is one.
- Prices are in rupees per unit, as listed in the catalog.
- Every user message starts with the app language and the user's current cart. Trust that cart and never make up cart contents.
- Messages may come from speech recognition and contain small mistakes. If a product name is close to exactly one catalog product, use that product.

ACTIONS (put them in the "actions" list, and leave the list empty when no action is needed):
- add_to_cart: use it when the user clearly asks to add an item. "product" must be the exact catalog name. "quantity" is a whole number of units (default 1). If the product is ambiguous, ask which one they mean instead of adding.
- place_order: use it only when the user clearly asks to place or confirm their order. Do NOT say the order is placed. The app will show the user a confirmation card, so just say you are getting it ready for their confirmation.
- Never claim an item was added unless you included an add_to_cart action for it.
''';
  }

  Schema _replySchema() {
    return Schema.object(
      properties: {
        'reply': Schema.string(
          description: 'The short message to show the user, in their language.',
        ),
        'actions': Schema.array(
          items: Schema.object(
            properties: {
              'type': Schema.string(
                description: 'Either add_to_cart or place_order.',
              ),
              'product': Schema.string(
                description: 'Exact catalog product name (add_to_cart only).',
              ),
              'quantity': Schema.integer(
                description: 'Number of units to add (add_to_cart only).',
              ),
            },
            optionalProperties: ['product', 'quantity'],
          ),
        ),
      },
      optionalProperties: ['actions'],
    );
  }

  // Sends one message. If the current model name is no longer valid, moves on
  // to the next name in kChatModelNames and tries again.
  Future<GenerateContentResponse> _askModel(String prompt) async {
    while (true) {
      try {
        return await _chat!.sendMessage(Content.text(prompt));
      } catch (e) {
        final text = e.toString().toLowerCase();
        final modelProblem = text.contains('not found') ||
            text.contains('404') ||
            text.contains('not supported') ||
            text.contains('no longer available') ||
            text.contains('deprecated') ||
            text.contains('quota') ||
            text.contains('429') ||
            text.contains('resource exhausted') ||
            text.contains('resource_exhausted') ||
            text.contains('rate limit');
        if (modelProblem && _modelIndex < kChatModelNames.length - 1) {
          debugPrint('Model ${kChatModelNames[_modelIndex]} failed: $e');
          _modelIndex++;
          _chat = _createChat(kChatModelNames[_modelIndex]);
          continue;
        }
        rethrow;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Cart helpers
  // ---------------------------------------------------------------------------

  int _cartTotal(List<Map<String, dynamic>> items) {
    return items.fold<int>(
      0,
      (sum, item) =>
          sum + (item['price'] as num).round() * (item['quantity'] as num).round(),
    );
  }

  String _cartSummary() {
    if (cartItems.isEmpty) return 'empty';
    final parts = cartItems
        .map((i) => '${i['name']} x${i['quantity']} (₹${i['price']} each)')
        .join('; ');
    return '$parts; total ₹${_cartTotal(cartItems)}';
  }

  int _parseQuantity(dynamic value) {
    final int q = value is num
        ? value.round()
        : (int.tryParse(value?.toString() ?? '') ?? 1);
    return q.clamp(1, 50).toInt();
  }

  // Uses the same item format as the products screen.
  void _addToCart(Map<String, dynamic> product, int quantity) {
    final index = cartItems.indexWhere((item) => item['name'] == product['name']);
    if (index != -1) {
      cartItems[index]['quantity'] =
          (cartItems[index]['quantity'] as num).round() + quantity;
    } else {
      final price = product['price'];
      cartItems.add({
        'name': product['name'],
        'price': price is num ? price.round() : 0,
        'brand': product['brand'],
        'unit': product['unit'],
        'quantity': quantity,
        'imageUrl': product['imageUrl'] ?? '',
      });
    }

    // A confirmation card for the old cart is no longer correct.
    for (final m in _messages) {
      if (m.isOrderCard && m.status == 'pending') m.status = 'outdated';
    }
  }

  // ---------------------------------------------------------------------------
  // Voice input
  // ---------------------------------------------------------------------------

  // While testing, voice steps are written into the chat as small orange
  // notes (same switch as the error details) so problems can be seen on the
  // phone without a cable.
  void _voiceLog(String text) {
    debugPrint('Voice: $text');
    if (!kShowErrorDetails || !mounted) return;
    setState(() {
      _messages.add(
        _ChatMessage(text: 'Voice: $text', isUser: false, isDebug: true),
      );
    });
    _scrollToBottom();
  }

  // Any error inside the voice steps is shown as an orange note instead of
  // disappearing silently.
  Future<void> _toggleListening(String lang) async {
    try {
      await _toggleListeningInner(lang);
    } catch (e) {
      _voiceLog('problem: $e');
      if (mounted) setState(() => _isListening = false);
    }
  }

  Future<void> _toggleListeningInner(String lang) async {
    _voiceLog('mic tapped (already listening: $_isListening)');

    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
      return;
    }

    final status = await Permission.microphone.request();
    if (!mounted) return;
    _voiceLog('microphone permission: ${status.name}');
    if (status != PermissionStatus.granted) {
      setState(() {
        _messages.add(_ChatMessage(text: _t(lang, 'micDenied'), isUser: false));
      });
      _scrollToBottom();
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        _voiceLog('status: $status');
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        _voiceLog('error: ${error.errorMsg}');
        if (!mounted) return;
        setState(() => _isListening = false);
        // If the phone does not have this speech language, try the phone's
        // own default language once.
        if (error.errorMsg.toLowerCase().contains('language') &&
            _lastLocaleTried != null) {
          _lastLocaleTried = null;
          _voiceLog('language not available, using phone default');
          _startListening(null);
        }
      },
    );
    if (!mounted) return;
    _voiceLog('speech recognition available: $available');
    if (!available) {
      setState(() {
        _messages
            .add(_ChatMessage(text: _t(lang, 'micUnavailable'), isUser: false));
      });
      _scrollToBottom();
      return;
    }

    // Start listening straight away. An earlier version looked up the phone's
    // language list first, but this phone never answers that, so the first
    // words were lost during the 3 second wait.
    if (!mounted) return;
    _lastLocaleTried = _localeFor(lang);
    _inputController.clear();
    _startListening(_lastLocaleTried);
  }

  void _startListening(String? localeId) {
    setState(() => _isListening = true);
    _voiceLog('starting to listen (${localeId ?? 'phone default language'})');

    _speech
        .listen(
          onResult: (result) {
            if (!mounted) return;
            setState(() {
              _inputController.text = result.recognizedWords;
              _inputController.selection = TextSelection.collapsed(
                offset: _inputController.text.length,
              );
            });
            if (result.finalResult) {
              _voiceLog('heard: "${result.recognizedWords}"');
              setState(() => _isListening = false);
              if (kAutoSendVoice && result.recognizedWords.trim().isNotEmpty) {
                _sendMessage();
              }
            }
          },
          localeId: localeId,
        )
        .catchError((Object e) {
      _voiceLog('listen failed: $e');
      if (mounted) setState(() => _isListening = false);
    });
  }

  // ---------------------------------------------------------------------------
  // Sending a message
  // ---------------------------------------------------------------------------

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending || _chat == null) return;

    final lang = Provider.of<LanguageProvider>(context, listen: false).language;

    if (_isListening) {
      _speech.stop();
      _isListening = false;
    }

    _inputController.clear();
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final prompt = 'App language: ${_languageName(lang)}\n'
          'Current cart: ${_cartSummary()}\n'
          'User message: $text';

      final response = await _askModel(prompt);
      final raw = response.text ?? '';

      // The model is asked for JSON; fall back to plain text if it is not.
      String reply = '';
      List<dynamic> actions = [];
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        reply = (data['reply'] ?? '').toString().trim();
        actions = (data['actions'] as List<dynamic>?) ?? [];
      } catch (_) {
        reply = raw.trim();
      }

      // The app, not the model, decides what actually happens.
      final added = <String>[];
      final failed = <String>[];
      bool wantsOrder = false;

      for (final action in actions) {
        if (action is! Map) continue;
        final type = (action['type'] ?? '').toString();

        if (type == 'add_to_cart') {
          final name = (action['product'] ?? '').toString().trim();
          final quantity = _parseQuantity(action['quantity']);
          final product = _productsByName[name.toLowerCase()];
          if (product == null) {
            failed.add(name);
            continue;
          }
          _addToCart(product, quantity);
          added.add('${product['name']} × $quantity');
        } else if (type == 'place_order') {
          wantsOrder = true;
        }
      }

      if (!mounted) return;
      setState(() {
        if (failed.isEmpty) {
          if (reply.isNotEmpty) {
            _messages.add(_ChatMessage(text: reply, isUser: false));
          }
        } else {
          _messages.add(_ChatMessage(
            text: '${_t(lang, 'notFound')}: ${failed.join(', ')}',
            isUser: false,
          ));
        }

        if (added.isNotEmpty) {
          _messages.add(_ChatMessage(
            text: '🛒 ${_t(lang, 'added')}: ${added.join(', ')}',
            isUser: false,
          ));
        }

        if (wantsOrder) {
          if (cartItems.isEmpty) {
            _messages.add(
                _ChatMessage(text: _t(lang, 'emptyCart'), isUser: false));
          } else {
            for (final m in _messages) {
              if (m.isOrderCard && m.status == 'pending') m.status = 'outdated';
            }
            _messages.add(_ChatMessage(
              text: '',
              isUser: false,
              items: cartItems.map((e) => Map<String, dynamic>.from(e)).toList(),
              total: _cartTotal(cartItems),
            ));
          }
        }

        _isSending = false;
      });
    } catch (e) {
      debugPrint('Chat error: $e');
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: _t(lang, 'error'), isUser: false));
        if (kShowErrorDetails) {
          _messages.add(_ChatMessage(
            text: 'Details (${kChatModelNames[_modelIndex]}): ${_shorten(e)}',
            isUser: false,
            isDebug: true,
          ));
        }
        _isSending = false;
      });
    }
    _scrollToBottom();
  }

  // ---------------------------------------------------------------------------
  // Placing the order. Only runs when the user taps Confirm on the card.
  // ---------------------------------------------------------------------------

  Future<void> _confirmOrder(_ChatMessage card, String lang) async {
    if (_placingOrder || card.status != 'pending') return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _messages.add(_ChatMessage(text: _t(lang, 'signIn'), isUser: false));
      });
      _scrollToBottom();
      return;
    }

    // The cart must still match what the card showed.
    final currentTotal = _cartTotal(cartItems);
    if (cartItems.isEmpty || currentTotal != card.total) {
      setState(() => card.status = 'outdated');
      _scrollToBottom();
      return;
    }

    setState(() => _placingOrder = true);

    try {
      // Same fields as the cart screen, so order history shows it normally.
      await FirebaseFirestore.instance.collection('orders').add({
        'userId': user.uid,
        'items': cartItems
            .map((item) => {
                  'name': item['name'],
                  'price': item['price'],
                  'quantity': item['quantity'],
                  'unit': item['unit'],
                  'brand': item['brand'],
                  'imageUrl': item['imageUrl'] ?? '',
                })
            .toList(),
        'totalAmount': currentTotal,
        'orderDate': DateTime.now(),
        'status': 'Placed',
      });

      if (!mounted) return;
      setState(() {
        card.status = 'confirmed';
        cartItems.clear();
        _messages.add(_ChatMessage(
          text: '✅ ${AppStrings.get('order_placed', lang)}  ₹$currentTotal',
          isUser: false,
        ));
        _placingOrder = false;
      });
    } catch (e) {
      debugPrint('Order error: $e');
      if (!mounted) return;
      setState(() {
        _messages
            .add(_ChatMessage(text: _t(lang, 'orderFailed'), isUser: false));
        if (kShowErrorDetails) {
          _messages.add(_ChatMessage(
            text: 'Details: ${_shorten(e)}',
            isUser: false,
            isDebug: true,
          ));
        }
        _placingOrder = false;
      });
    }
    _scrollToBottom();
  }

  void _cancelOrder(_ChatMessage card) {
    if (card.status != 'pending') return;
    setState(() => card.status = 'cancelled');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context).language;
    final canType = !_loading && !_initFailed;

    return PopScope(
      // Whatever way the user leaves (back arrow or phone back button),
      // the updated cart goes back to the home screen.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(cartItems);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.green,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Row(
            children: [
              const Icon(Icons.chat_bubble, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _t(lang, 'title'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(child: _buildBody(lang)),
            _buildInputBar(lang, canType),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(String lang) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.green));
    }

    if (_initFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                _t(lang, 'error'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
              if (kShowErrorDetails) ...[
                const SizedBox(height: 12),
                SelectableText(
                  'Details: $_initError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _retryInit,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: Text(
                  _t(lang, 'retry'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shopping_basket, size: 56, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                _t(lang, 'welcome'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _bubble(_ChatMessage(text: '…', isUser: false));
        }
        final m = _messages[index];
        return m.isOrderCard ? _orderCard(m, lang) : _bubble(m);
      },
    );
  }

  Widget _bubble(_ChatMessage m) {
    if (m.isDebug) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: SelectableText(
            m.text,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ),
      );
    }

    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: m.isUser ? Colors.green : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          m.text,
          style: TextStyle(
            fontSize: 15,
            color: m.isUser ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _orderCard(_ChatMessage m, String lang) {
    final pending = m.status == 'pending';
    final items = m.items ?? [];

    String statusText;
    switch (m.status) {
      case 'confirmed':
        statusText = '✅ ${AppStrings.get('order_placed', lang)}';
        break;
      case 'cancelled':
        statusText = _t(lang, 'cancelled');
        break;
      default:
        statusText = _t(lang, 'cartChanged');
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(lang, 'yourOrder'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${item['name']} × ${item['quantity']}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text(
                      '₹${(item['price'] as num).round() * (item['quantity'] as num).round()}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.get('total', lang),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '₹${m.total}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (pending)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _placingOrder ? null : () => _cancelOrder(m),
                      child: Text(_t(lang, 'cancel')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _placingOrder ? null : () => _confirmOrder(m, lang),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      child: _placingOrder
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              AppStrings.get('place_order', lang),
                              style: const TextStyle(color: Colors.white),
                            ),
                    ),
                  ),
                ],
              )
            else
              Text(
                statusText,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(String lang, bool canType) {
    final canSend = canType && !_isSending;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                enabled: canType,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: _isListening ? _t(lang, 'listening') : _t(lang, 'hint'),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: Colors.green, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Microphone button
            Container(
              decoration: BoxDecoration(
                color: !canSend
                    ? Colors.grey
                    : (_isListening ? Colors.red : Colors.green.shade700),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  color: Colors.white,
                ),
                onPressed: canSend ? () => _toggleListening(lang) : null,
              ),
            ),
            const SizedBox(width: 8),
            // Send button
            Container(
              decoration: BoxDecoration(
                color: canSend ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: canSend ? _sendMessage : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}