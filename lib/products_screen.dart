import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'cart_screen.dart';
import 'language_provider.dart';
import 'app_strings.dart';

class ProductsScreen extends StatefulWidget {
  final String category;
  final List<Map<String, dynamic>> cartItems;
  final String? subcategory; // null means show all in category
  const ProductsScreen({
    super.key,
    required this.category,
    required this.cartItems,
    this.subcategory,
  });

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late List<Map<String, dynamic>> cartItems;

  @override
  void initState() {
    super.initState();
    cartItems = List.from(widget.cartItems);
  }

  void addToCart(Map<String, dynamic> product, String lang) {
    setState(() {
      int existingIndex = cartItems.indexWhere(
        (item) => item['name'] == product['name'],
      );
      if (existingIndex != -1) {
        cartItems[existingIndex]['quantity']++;
      } else {
        cartItems.add({
          'name': product['name'],
          'price': product['price'],
          'brand': product['brand'],
          'unit': product['unit'],
          'quantity': 1,
        });
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lang == 'en'
              ? '${product['name']} added to cart!'
              : lang == 'te'
                  ? '${product['name']} కార్ట్‌కి జోడించబడింది!'
                  : '${product['name']} कार्ट में जोड़ा गया!',
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.green,
      ),
    );
  }

  String getScreenTitle(String lang) {
    // If subcategory exists show subcategory name, else show category name
    if (widget.subcategory != null) {
      return widget.subcategory![0].toUpperCase() +
          widget.subcategory!.substring(1);
    }
    switch (widget.category.toLowerCase()) {
      case 'vegetables': return AppStrings.get('vegetables', lang);
      case 'fruits': return AppStrings.get('fruits', lang);
      case 'dairy': return AppStrings.get('dairy', lang);
      case 'grains': return AppStrings.get('grains', lang);
      case 'meat': return AppStrings.get('meat', lang);
      case 'beverages': return AppStrings.get('beverages', lang);
      default: return widget.category[0].toUpperCase() + widget.category.substring(1);
    }
  }

  // Build Firestore query based on category and subcategory
  Stream<QuerySnapshot> getProductsStream() {
    if (widget.subcategory != null) {
      // Voice search — filter by subcategory
      return FirebaseFirestore.instance
          .collection('products')
          .where('subcategory', isEqualTo: widget.subcategory)
          .snapshots();
    } else {
      // Category card tap — show all in category
      return FirebaseFirestore.instance
          .collection('products')
          .where('category', isEqualTo: widget.category)
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final lang = langProvider.language;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context, cartItems);
          },
        ),
        title: Text(
          getScreenTitle(lang),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
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
                  if (updatedCart != null) {
                    setState(() => cartItems = updatedCart);
                  }
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
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: getProductsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.green),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                'No products found!',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var product = snapshot.data!.docs[index].data()
                  as Map<String, dynamic>;

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.shopping_basket,
                        color: Colors.green,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product['name'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product['brand'],
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${product['price']} / ${product['unit']}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => addToCart(product, lang),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        AppStrings.get('add', lang),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}