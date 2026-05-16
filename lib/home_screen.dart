import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String userName = '';
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _recognizedText = 'Tap the mic and speak...';
  String _foundProduct = '';

  final Map<String, String> wordToProduct = {
    // English
    'milk': 'Milk',
    'rice': 'Rice',
    'sugar': 'Sugar',
    'onion': 'Onion',
    'tomato': 'Tomato',
    'potato': 'Potato',
    'banana': 'Banana',
    'apple': 'Apple',
    'bread': 'Bread',
    'egg': 'Egg',
    'eggs': 'Egg',
    'water': 'Water',
    'oil': 'Oil',

    // Telugu script
    'పాలు': 'Milk',
    'బియ్యం': 'Rice',
    'చక్కెర': 'Sugar',
    'ఉల్లిపాయ': 'Onion',
    'టొమాటో': 'Tomato',
    'బంగాళదుంప': 'Potato',
    'అరటిపండు': 'Banana',
    'ఆపిల్': 'Apple',
    'బ్రెడ్': 'Bread',
    'గుడ్డు': 'Egg',
    'నీళ్ళు': 'Water',
    'నూనె': 'Oil',

    // Hindi script
    'दूध': 'Milk',
    'चावल': 'Rice',
    'चीनी': 'Sugar',
    'प्याज': 'Onion',
    'टमाटर': 'Tomato',
    'आलू': 'Potato',
    'केला': 'Banana',
    'सेब': 'Apple',
    'ब्रेड': 'Bread',
    'अंडा': 'Egg',
    'पानी': 'Water',
    'तेल': 'Oil',

    // Telugu transliterated (spoken in English letters)
    'paalu': 'Milk',
    'palu': 'Milk',
    'biyyam': 'Rice',
    'biyam': 'Rice',
    'chakkera': 'Sugar',
    'chakera': 'Sugar',
    'ullipaya': 'Onion',
    'ullipayalu': 'Onion',
    'bangaladumpa': 'Potato',
    'aratipandu': 'Banana',
    'guddu': 'Egg',
    'neellu': 'Water',
    'noone': 'Oil',
    'nune': 'Oil',

    // Hindi transliterated (spoken in English letters)
    'doodh': 'Milk',
    'dudh': 'Milk',
    'chawal': 'Rice',
    'chini': 'Sugar',
    'pyaaz': 'Onion',
    'pyaz': 'Onion',
    'aloo': 'Potato',
    'kela': 'Banana',
    'seb': 'Apple',
    'anda': 'Egg',
    'pani': 'Water',
    'tel': 'Oil',
  };

  @override
  void initState() {
    super.initState();
    getUserName();
  }

  Future<void> getUserName() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      setState(() {
        userName = doc['name'];
      });
    }
  }

  Future<void> startListening() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      setState(() {
        _recognizedText = 'Microphone permission denied!';
      });
      return;
    }

    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() {
            _isListening = false;
          });
        }
      },
      onError: (error) {
        setState(() {
          _isListening = false;
          _recognizedText = 'Error: ${error.errorMsg}';
        });
      },
    );

    if (available) {
      setState(() {
        _isListening = true;
        _recognizedText = 'Listening...';
        _foundProduct = '';
      });

      _speech.listen(
        onResult: (result) {
          setState(() {
            _recognizedText = result.recognizedWords;
            _foundProduct = findProduct(result.recognizedWords);
          });
        },
        localeId: 'en_IN',
      );
    } else {
      setState(() {
        _recognizedText = 'Microphone not available!';
      });
    }
  }

  void stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
    });
  }

  String findProduct(String spokenText) {
    String lowerText = spokenText.toLowerCase();

    // Check direct word match first
    for (String key in wordToProduct.keys) {
      if (lowerText.contains(key.toLowerCase())) {
        return wordToProduct[key]!;
      }
    }

    // Smart matching for common variations
    if (lowerText.contains('mil')) return 'Milk';
    if (lowerText.contains('ric')) return 'Rice';
    if (lowerText.contains('sug')) return 'Sugar';
    if (lowerText.contains('oni')) return 'Onion';
    if (lowerText.contains('tom')) return 'Tomato';
    if (lowerText.contains('pot')) return 'Potato';
    if (lowerText.contains('ban')) return 'Banana';
    if (lowerText.contains('app')) return 'Apple';
    if (lowerText.contains('bre')) return 'Bread';
    if (lowerText.contains('egg')) return 'Egg';
    if (lowerText.contains('wat')) return 'Water';
    if (lowerText.contains('oil')) return 'Oil';
    if (lowerText.contains('pal')) return 'Milk';
    if (lowerText.contains('paa')) return 'Milk';
    if (lowerText.contains('biy')) return 'Rice';
    if (lowerText.contains('chak')) return 'Sugar';
    if (lowerText.contains('ulli')) return 'Onion';
    if (lowerText.contains('gudd')) return 'Egg';
    if (lowerText.contains('noon')) return 'Oil';
    if (lowerText.contains('dood')) return 'Milk';
    if (lowerText.contains('chaw')) return 'Rice';
    if (lowerText.contains('chin')) return 'Sugar';
    if (lowerText.contains('pyaa')) return 'Onion';
    if (lowerText.contains('aloo')) return 'Potato';
    if (lowerText.contains('kela')) return 'Banana';
    if (lowerText.contains('pani')) return 'Water';

    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: const Row(
          children: [
            Icon(Icons.shopping_cart, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'VoiceCart',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hi $userName! 👋',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'What do you need today?',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),

            // Voice Button
            Center(
              child: GestureDetector(
                onTap: _isListening ? stopListening : startListening,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    color: _isListening ? Colors.red : Colors.green,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _isListening
                            ? Colors.red.withOpacity(0.4)
                            : Colors.green.withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        size: 60,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isListening ? 'Listening...' : 'Tap to Speak',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Recognized Text Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'You said:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _recognizedText,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            // Found Product
            if (_foundProduct.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'Found: $_foundProduct',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Categories Title
            const Text(
              'Categories',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            // Categories Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                buildCategoryCard('🥦', 'Vegetables', Colors.green.shade50),
                buildCategoryCard('🍎', 'Fruits', Colors.red.shade50),
                buildCategoryCard('🥛', 'Dairy', Colors.blue.shade50),
                buildCategoryCard('🍚', 'Grains', Colors.orange.shade50),
                buildCategoryCard('🍗', 'Meat', Colors.brown.shade50),
                buildCategoryCard('🧃', 'Beverages', Colors.purple.shade50),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildCategoryCard(String emoji, String name, Color color) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 40),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}