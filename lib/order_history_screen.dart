import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'language_provider.dart';

// How long each step takes after an order is placed. Change these two
// numbers to make the steps faster or slower.
//   0 to kShipAfter        -> Placed (the order can be cancelled)
//   kShipAfter to kDeliverAfter -> Shipped
//   after kDeliverAfter    -> Delivered
const Duration kShipAfter = Duration(minutes: 2);
const Duration kDeliverAfter = Duration(minutes: 4);

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  // Created once. A new stream on every rebuild would restart the list.
  late final Stream<QuerySnapshot> _ordersStream;
  Timer? _ticker;

  static const List<String> _steps = ['Placed', 'Shipped', 'Delivered'];

  static const Map<String, Map<String, String>> _strings = {
    'placed': {
      'en': 'Placed',
      'te': 'ఆర్డర్ చేయబడింది',
      'hi': 'ऑर्डर दिया गया',
    },
    'shipped': {
      'en': 'Shipped',
      'te': 'పంపబడింది',
      'hi': 'भेजा गया',
    },
    'delivered': {
      'en': 'Delivered',
      'te': 'డెలివరీ అయింది',
      'hi': 'डिलीवर हुआ',
    },
    'cancelled': {
      'en': 'Cancelled',
      'te': 'రద్దు చేయబడింది',
      'hi': 'रद्द किया गया',
    },
    'cancelOrder': {
      'en': 'Cancel Order',
      'te': 'ఆర్డర్ రద్దు చేయి',
      'hi': 'ऑर्डर रद्द करें',
    },
    'cancelTimeLeft': {
      'en': 'Time left to cancel',
      'te': 'రద్దు చేయడానికి మిగిలిన సమయం',
      'hi': 'रद्द करने के लिए शेष समय',
    },
    'deliveryIn': {
      'en': 'Delivery in',
      'te': 'డెలివరీకి మిగిలిన సమయం',
      'hi': 'डिलीवरी में शेष समय',
    },
    'deliveredInfo': {
      'en': 'Your order has been delivered',
      'te': 'మీ ఆర్డర్ డెలివరీ అయింది',
      'hi': 'आपका ऑर्डर डिलीवर हो गया है',
    },
    'cancelledInfo': {
      'en': 'This order was cancelled',
      'te': 'ఈ ఆర్డర్ రద్దు చేయబడింది',
      'hi': 'यह ऑर्डर रद्द कर दिया गया',
    },
    'confirmCancel': {
      'en': 'Cancel this order?',
      'te': 'ఈ ఆర్డర్‌ను రద్దు చేయాలా?',
      'hi': 'क्या आप यह ऑर्डर रद्द करना चाहते हैं?',
    },
    'yesCancel': {
      'en': 'Yes, cancel',
      'te': 'అవును, రద్దు చేయి',
      'hi': 'हाँ, रद्द करें',
    },
    'no': {
      'en': 'No',
      'te': 'వద్దు',
      'hi': 'नहीं',
    },
    'tooLate': {
      'en': 'Too late, this order has already shipped.',
      'te': 'ఆలస్యమైంది, ఈ ఆర్డర్ ఇప్పటికే పంపబడింది.',
      'hi': 'देर हो गई, यह ऑर्डर पहले ही भेज दिया गया है।',
    },
    'cancelFailed': {
      'en': 'Could not cancel the order. Please try again.',
      'te': 'ఆర్డర్ రద్దు చేయలేకపోయాము. దయచేసి మళ్లీ ప్రయత్నించండి.',
      'hi': 'ऑर्डर रद्द नहीं हो सका। कृपया फिर से कोशिश करें।',
    },
    'loadFailed': {
      'en': 'Could not load your orders. Please try again.',
      'te': 'మీ ఆర్డర్లను లోడ్ చేయలేకపోయాము. దయచేసి మళ్లీ ప్రయత్నించండి.',
      'hi': 'आपके ऑर्डर लोड नहीं हो सके। कृपया फिर से कोशिश करें।',
    },
  };

  String _t(String lang, String key) =>
      _strings[key]?[lang] ?? _strings[key]?['en'] ?? key;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _ordersStream = FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: user?.uid)
        .orderBy('orderDate', descending: true)
        .snapshots();

    // Refresh every second so the countdowns and statuses move on their own.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Status logic. The status is worked out from the time the order was placed.
  // Only "Cancelled" is stored in Firestore.
  // ---------------------------------------------------------------------------

  String _effectiveStatus(Map<String, dynamic> order, DateTime orderDate) {
    final stored = (order['status'] ?? 'Placed').toString();
    if (stored == 'Cancelled') return 'Cancelled';

    final age = DateTime.now().difference(orderDate);
    String byTime = 'Placed';
    if (age >= kDeliverAfter) {
      byTime = 'Delivered';
    } else if (age >= kShipAfter) {
      byTime = 'Shipped';
    }

    // If a later status was set by hand in Firestore, keep that one.
    final storedRank = _steps.indexOf(stored);
    final timeRank = _steps.indexOf(byTime);
    return _steps[storedRank > timeRank ? storedRank : timeRank];
  }

  String _mmss(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _statusLabel(String status, String lang) {
    switch (status) {
      case 'Shipped':
        return _t(lang, 'shipped');
      case 'Delivered':
        return _t(lang, 'delivered');
      case 'Cancelled':
        return _t(lang, 'cancelled');
      default:
        return _t(lang, 'placed');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Shipped':
        return Colors.blue;
      case 'Delivered':
        return Colors.green;
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.orange.shade700;
    }
  }

  // ---------------------------------------------------------------------------
  // Cancelling
  // ---------------------------------------------------------------------------

  Future<void> _confirmCancel(
    DocumentReference ref,
    Map<String, dynamic> order,
    DateTime orderDate,
    String lang,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t(lang, 'confirmCancel')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t(lang, 'no')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              _t(lang, 'yesCancel'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    // Time may have passed while the question was open.
    if (_effectiveStatus(order, orderDate) != 'Placed') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t(lang, 'tooLate'))),
      );
      return;
    }

    try {
      await ref.update({
        'status': 'Cancelled',
        'cancelledAt': DateTime.now(),
      });
    } catch (e) {
      debugPrint('Cancel order error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t(lang, 'cancelFailed'))),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // UI pieces
  // ---------------------------------------------------------------------------

  Widget _stepper(int step, String lang) {
    final labels = [
      _t(lang, 'placed'),
      _t(lang, 'shipped'),
      _t(lang, 'delivered'),
    ];
    final children = <Widget>[];

    for (var i = 0; i < 3; i++) {
      final done = i <= step;
      children.add(
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: done ? Colors.green : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: done
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              labels[i],
              style: TextStyle(
                fontSize: 11,
                color: done ? Colors.green.shade800 : Colors.grey,
                fontWeight: i == step ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      );
      if (i < 2) {
        children.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Container(
                height: 2,
                color: i < step ? Colors.green : Colors.grey.shade300,
              ),
            ),
          ),
        );
      }
    }

    return Row(children: children);
  }

  Widget _footer({
    required String status,
    required Duration age,
    required DocumentReference ref,
    required Map<String, dynamic> order,
    required DateTime orderDate,
    required String lang,
  }) {
    Widget content;

    if (status == 'Placed') {
      content = Row(
        children: [
          Expanded(
            child: Text(
              '${_t(lang, 'cancelTimeLeft')}: ${_mmss(kShipAfter - age)}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
          OutlinedButton(
            onPressed: () => _confirmCancel(ref, order, orderDate, lang),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            child: Text(_t(lang, 'cancelOrder')),
          ),
        ],
      );
    } else if (status == 'Shipped') {
      content = Text(
        '${_t(lang, 'deliveryIn')}: ${_mmss(kDeliverAfter - age)}',
        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
      );
    } else if (status == 'Delivered') {
      content = Text(
        _t(lang, 'deliveredInfo'),
        style: TextStyle(fontSize: 13, color: Colors.green.shade800),
      );
    } else {
      content = Text(
        _t(lang, 'cancelledInfo'),
        style: const TextStyle(fontSize: 13, color: Colors.red),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: content,
    );
  }

  Widget _orderCard(QueryDocumentSnapshot doc, String lang) {
    final order = doc.data() as Map<String, dynamic>;
    final List items = order['items'] ?? [];
    final DateTime orderDate = (order['orderDate'] as Timestamp).toDate();
    final status = _effectiveStatus(order, orderDate);
    final age = DateTime.now().difference(orderDate);
    final step = _steps.indexOf(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Column(
        children: [
          // Order Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${orderDate.day}/${orderDate.month}/${orderDate.year}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${orderDate.hour}:${orderDate.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(status, lang),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Progress: Placed - Shipped - Delivered
          if (status != 'Cancelled')
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: _stepper(step, lang),
            ),

          // Order Items
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, itemIndex) {
              var item = items[itemIndex];
              String? imageUrl = item['imageUrl'];

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.shopping_basket,
                                    color: Colors.green,
                                    size: 24,
                                  );
                                },
                              ),
                            )
                          : const Icon(
                              Icons.shopping_basket,
                              color: Colors.green,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name'],
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${item['quantity']} x ₹${item['price']}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${item['price'] * item['quantity']}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Order Total
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lang == 'en'
                      ? 'Total Amount'
                      : lang == 'te'
                          ? 'మొత్తం'
                          : 'कुल राशि',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '₹${order['totalAmount']}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),

          // Status line, countdown and Cancel button
          _footer(
            status: status,
            age: age,
            ref: doc.reference,
            order: order,
            orderDate: orderDate,
            lang: lang,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final lang = langProvider.language;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: Text(
          lang == 'en'
              ? 'Order History'
              : lang == 'te'
                  ? 'ఆర్డర్ చరిత్ర'
                  : 'ऑर्डर इतिहास',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.green),
            );
          }

          if (snapshot.hasError) {
            debugPrint('Order history error: ${snapshot.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _t(lang, 'loadFailed'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.receipt_long, size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    lang == 'en'
                        ? 'No orders yet!'
                        : lang == 'te'
                            ? 'ఇంకా ఆర్డర్లు లేవు!'
                            : 'अभी तक कोई ऑर्डर नहीं!',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) => _orderCard(docs[index], lang),
          );
        },
      ),
    );
  }
}