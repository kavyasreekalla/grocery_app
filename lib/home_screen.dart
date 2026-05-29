import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'products_screen.dart';
import 'cart_screen.dart';
import 'profile_screen.dart';
import 'language_provider.dart';
import 'app_strings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
final TextEditingController _searchController = TextEditingController();
class _HomeScreenState extends State<HomeScreen> {
  String userName = '';
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _recognizedText = '';
  String _foundProduct = '';
  List<Map<String, dynamic>> cartItems = [];
  @override
void dispose() {
  _searchController.dispose();
  super.dispose();
}

  final Map<String, String> wordToProduct = {
    'milk': 'Milk', 'rice': 'Rice', 'sugar': 'Sugar',
    'onion': 'Onion', 'tomato': 'Tomato', 'potato': 'Potato',
    'banana': 'Banana', 'apple': 'Apple', 'bread': 'Bread',
    'egg': 'Egg', 'eggs': 'Egg', 'water': 'Water', 'oil': 'Oil',
    'butter': 'Butter', 'curd': 'Curd', 'chicken': 'Chicken',
    'mango': 'Mango', 'dal': 'Dal', 'poha': 'Poha',
    'juice': 'Juice', 'cola': 'Cola', 'coke': 'Cola',
    'పాలు': 'Milk', 'బియ్యం': 'Rice', 'చక్కెర': 'Sugar',
    'ఉల్లిపాయ': 'Onion', 'టొమాటో': 'Tomato', 'బంగాళదుంప': 'Potato',
    'అరటిపండు': 'Banana', 'ఆపిల్': 'Apple', 'బ్రెడ్': 'Bread',
    'గుడ్డు': 'Egg', 'నీళ్ళు': 'Water', 'నూనె': 'Oil',
    'వెన్న': 'Butter', 'పెరుగు': 'Curd', 'కోడి': 'Chicken',
    'మామిడికాయ': 'Mango', 'పప్పు': 'Dal', 'అటుకులు': 'Poha',
    'दूध': 'Milk', 'चावल': 'Rice', 'चीनी': 'Sugar',
    'प्याज': 'Onion', 'टमाटर': 'Tomato', 'आलू': 'Potato',
    'केला': 'Banana', 'सेब': 'Apple', 'ब्रेड': 'Bread',
    'अंडा': 'Egg', 'पानी': 'Water', 'तेल': 'Oil',
    'मक्खन': 'Butter', 'दही': 'Curd', 'मुर्गी': 'Chicken',
    'आम': 'Mango', 'दाल': 'Dal',
    'paalu': 'Milk', 'palu': 'Milk', 'biyyam': 'Rice', 'biyam': 'Rice',
    'chakkera': 'Sugar', 'chakera': 'Sugar', 'ullipaya': 'Onion',
    'ullipayalu': 'Onion', 'bangaladumpa': 'Potato', 'aratipandu': 'Banana',
    'guddu': 'Egg', 'neellu': 'Water', 'noone': 'Oil', 'nune': 'Oil',
    'venna': 'Butter', 'perugu': 'Curd', 'kodi': 'Chicken',
    'mamidikaya': 'Mango', 'pappu': 'Dal', 'atukulu': 'Poha',
    'doodh': 'Milk', 'dudh': 'Milk', 'chawal': 'Rice', 'chini': 'Sugar',
    'pyaaz': 'Onion', 'pyaz': 'Onion', 'aloo': 'Potato', 'kela': 'Banana',
    'seb': 'Apple', 'anda': 'Egg', 'pani': 'Water', 'tel': 'Oil',
    'makkhan': 'Butter', 'dahi': 'Curd', 'murgi': 'Chicken',
    'aam': 'Mango', 'daal': 'Dal',
  };

  String getCategory(String product) {
    switch (product.toLowerCase()) {
      case 'milk': return 'milk';
      case 'rice': return 'rice';
      case 'sugar': return 'sugar';
      case 'oil': return 'oil';
      case 'onion': return 'vegetables';
      case 'tomato': return 'vegetables';
      case 'potato': return 'vegetables';
      case 'banana': return 'fruits';
      case 'apple': return 'fruits';
      case 'mango': return 'fruits';
      case 'bread': return 'grains';
      case 'dal': return 'grains';
      case 'poha': return 'grains';
      case 'egg': return 'meat';
      case 'chicken': return 'meat';
      case 'butter': return 'dairy';
      case 'curd': return 'dairy';
      case 'water': return 'beverages';
      case 'juice': return 'beverages';
      case 'cola': return 'beverages';
      default: return product.toLowerCase();
    }
  }

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
      setState(() => _recognizedText = 'Microphone permission denied!');
      return;
    }

    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
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
      setState(() => _recognizedText = 'Microphone not available!');
    }
  }

  void stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  void navigateToProducts(String category, {String? subcategory}) async {
    final updatedCart = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductsScreen(
          category: category,
          cartItems: cartItems,
          subcategory: subcategory,
        ),
      ),
    );
    setState(() {
      cartItems = updatedCart ?? [];
    });
  }

  String findProduct(String spokenText) {
    String lowerText = spokenText.toLowerCase();

    for (String key in wordToProduct.keys) {
      if (lowerText.contains(key.toLowerCase())) {
        String product = wordToProduct[key]!;
        navigateToProducts(
          getCategory(product),
          subcategory: product.toLowerCase(),
        );
        return product;
      }
    }

    if (lowerText.contains('mil') || lowerText.contains('pal') || lowerText.contains('dood')) { navigateToProducts('milk', subcategory: 'milk'); return 'Milk'; }
    if (lowerText.contains('ric') || lowerText.contains('biy') || lowerText.contains('chaw')) { navigateToProducts('rice', subcategory: 'rice'); return 'Rice'; }
    if (lowerText.contains('sug') || lowerText.contains('chak') || lowerText.contains('chin')) { navigateToProducts('sugar', subcategory: 'sugar'); return 'Sugar'; }
    if (lowerText.contains('oil') || lowerText.contains('noon') || lowerText.contains('tel')) { navigateToProducts('oil', subcategory: 'oil'); return 'Oil'; }
    if (lowerText.contains('oni') || lowerText.contains('ulli') || lowerText.contains('pyaa')) { navigateToProducts('vegetables', subcategory: 'onion'); return 'Onion'; }
    if (lowerText.contains('tom') || lowerText.contains('tamatar')) { navigateToProducts('vegetables', subcategory: 'tomato'); return 'Tomato'; }
    if (lowerText.contains('pot') || lowerText.contains('aloo') || lowerText.contains('dumpa')) { navigateToProducts('vegetables', subcategory: 'potato'); return 'Potato'; }
    if (lowerText.contains('ban') || lowerText.contains('kela') || lowerText.contains('arati')) { navigateToProducts('fruits', subcategory: 'banana'); return 'Banana'; }
    if (lowerText.contains('app') || lowerText.contains('seb')) { navigateToProducts('fruits', subcategory: 'apple'); return 'Apple'; }
    if (lowerText.contains('mang') || lowerText.contains('mamid') || lowerText.contains('aam')) { navigateToProducts('fruits', subcategory: 'mango'); return 'Mango'; }
    if (lowerText.contains('butt') || lowerText.contains('venna') || lowerText.contains('makk')) { navigateToProducts('dairy', subcategory: 'butter'); return 'Butter'; }
    if (lowerText.contains('curd') || lowerText.contains('peru') || lowerText.contains('dahi')) { navigateToProducts('dairy', subcategory: 'curd'); return 'Curd'; }
    if (lowerText.contains('bre') || lowerText.contains('bread')) { navigateToProducts('grains', subcategory: 'bread'); return 'Bread'; }
    if (lowerText.contains('dal') || lowerText.contains('pappu') || lowerText.contains('daal')) { navigateToProducts('grains', subcategory: 'dal'); return 'Dal'; }
    if (lowerText.contains('poha') || lowerText.contains('atuk')) { navigateToProducts('grains', subcategory: 'poha'); return 'Poha'; }
    if (lowerText.contains('atta') || lowerText.contains('flour')) { navigateToProducts('grains', subcategory: 'atta'); return 'Atta'; }
    if (lowerText.contains('egg') || lowerText.contains('gudd') || lowerText.contains('anda')) { navigateToProducts('meat', subcategory: 'egg'); return 'Egg'; }
    if (lowerText.contains('chick') || lowerText.contains('kodi') || lowerText.contains('murgi')) { navigateToProducts('meat', subcategory: 'chicken'); return 'Chicken'; }
    if (lowerText.contains('wat') || lowerText.contains('pani') || lowerText.contains('neel')) { navigateToProducts('beverages', subcategory: 'water'); return 'Water'; }
    if (lowerText.contains('juic') || lowerText.contains('ras')) { navigateToProducts('beverages', subcategory: 'juice'); return 'Juice'; }
    if (lowerText.contains('cola') || lowerText.contains('coke') || lowerText.contains('soda')) { navigateToProducts('beverages', subcategory: 'cola'); return 'Cola'; }

    return '';
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final lang = langProvider.language;

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
          GestureDetector(
            onTap: () => langProvider.toggleLanguage(),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                langProvider.languageLabel,
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart, color: Colors.white),
                onPressed: () async {
                  final updatedCart = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CartScreen(cartItems: cartItems),
                    ),
                  );
                  setState(() {
                    cartItems = updatedCart ?? [];
                  });
                },
              ),
              if (cartItems.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${cartItems.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppStrings.get('greeting', lang)} $userName! 👋',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.get('tagline', lang),
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            // Search Bar
Row(
  children: [
    Expanded(
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: AppStrings.get('search_hint', lang),
          prefixIcon: const Icon(Icons.search, color: Colors.green),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.green, width: 2),
          ),
        ),
        onSubmitted: (value) {
          if (value.isNotEmpty) {
            findProduct(value);
            _searchController.clear();
          }
        },
      ),
    ),
    const SizedBox(width: 8),
    ElevatedButton(
      onPressed: () {
        if (_searchController.text.isNotEmpty) {
          findProduct(_searchController.text);
          _searchController.clear();
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: const Icon(Icons.search, color: Colors.white),
    ),
  ],
),
const SizedBox(height: 24),

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
                        _isListening
                            ? AppStrings.get('listening', lang)
                            : AppStrings.get('tap_to_speak', lang),
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
                  Text(
                    AppStrings.get('you_said', lang),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _recognizedText.isEmpty
                        ? AppStrings.get('tap_to_speak', lang)
                        : _recognizedText,
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                ],
              ),
            ),

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
                      '${AppStrings.get('found', lang)}: $_foundProduct',
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

            Text(
              AppStrings.get('categories', lang),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                buildCategoryCard('🥦', AppStrings.get('vegetables', lang), Colors.green.shade50, 'vegetables'),
                buildCategoryCard('🍎', AppStrings.get('fruits', lang), Colors.red.shade50, 'fruits'),
                buildCategoryCard('🥛', AppStrings.get('dairy', lang), Colors.blue.shade50, 'dairy'),
                buildCategoryCard('🍚', AppStrings.get('grains', lang), Colors.orange.shade50, 'grains'),
                buildCategoryCard('🍗', AppStrings.get('meat', lang), Colors.brown.shade50, 'meat'),
                buildCategoryCard('🧃', AppStrings.get('beverages', lang), Colors.purple.shade50, 'beverages'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildCategoryCard(String emoji, String name, Color color, String category) {
    return GestureDetector(
      onTap: () => navigateToProducts(category),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
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