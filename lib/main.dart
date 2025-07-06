import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shimmer/shimmer.dart';
import 'package:lottie/lottie.dart';
import 'package:confetti/confetti.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:badges/badges.dart' as badges;
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  initializeService();
  runApp(MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'product_monitor_bg',
      initialNotificationTitle: 'Product Monitor',
      initialNotificationContent: 'Monitoring products in background',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NK Product Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: createMaterialColor(Color(0xFF6B46C1)),
        scaffoldBackgroundColor: Color(0xFFF8F9FA),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF6B46C1),
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF6B46C1),
          elevation: 4,
        ),
        dividerTheme: DividerThemeData(
          space: 0,
          thickness: 1,
          color: Colors.grey[200],
        ),
      ),
      home: ProductMonitorHome(),
    );
  }
}

MaterialColor createMaterialColor(Color color) {
  List strengths = <double>[.05];
  Map<int, Color> swatch = {};
  final int r = color.red, g = color.green, b = color.blue;

  for (int i = 1; i < 10; i++) {
    strengths.add(0.1 * i);
  }
  strengths.forEach((strength) {
    final double ds = 0.5 - strength;
    swatch[(strength * 1000).round()] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
      1,
    );
  });
  return MaterialColor(color.value, swatch);
}

class Product {
  final String id;
  final String url;
  final String title;
  final String price;
  final String availability;
  final DateTime lastChecked;
  final bool isAvailable;
  final bool trackAvailability;
  final bool trackPrice;
  final String initialPrice;
  final List<PriceHistory> priceHistory;
  final String? imageUrl;
  final String currency;
  final String domain;

  Product({
    required this.id,
    required this.url,
    required this.title,
    required this.price,
    required this.availability,
    required this.lastChecked,
    required this.isAvailable,
    this.trackAvailability = true,
    this.trackPrice = false,
    this.initialPrice = '',
    this.priceHistory = const [],
    this.imageUrl,
    this.currency = '₹',
    this.domain = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'price': price,
      'availability': availability,
      'lastChecked': lastChecked.toIso8601String(),
      'isAvailable': isAvailable,
      'trackAvailability': trackAvailability,
      'trackPrice': trackPrice,
      'initialPrice': initialPrice,
      'priceHistory': priceHistory.map((h) => h.toJson()).toList(),
      'imageUrl': imageUrl,
      'currency': currency,
      'domain': domain,
    };
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      url: json['url'],
      title: json['title'],
      price: json['price'],
      availability: json['availability'],
      lastChecked: DateTime.parse(json['lastChecked']),
      isAvailable: json['isAvailable'],
      trackAvailability: json['trackAvailability'] ?? true,
      trackPrice: json['trackPrice'] ?? false,
      initialPrice: json['initialPrice'] ?? json['price'] ?? '',
      priceHistory: (json['priceHistory'] as List<dynamic>?)
          ?.map((h) => PriceHistory.fromJson(h))
          .toList() ?? [],
      imageUrl: json['imageUrl'],
      currency: json['currency'] ?? '₹',
      domain: json['domain'] ?? '',
    );
  }

  Product copyWith({
    String? price,
    String? availability,
    DateTime? lastChecked,
    bool? isAvailable,
    bool? trackAvailability,
    bool? trackPrice,
    String? initialPrice,
    List<PriceHistory>? priceHistory,
    String? imageUrl,
    String? currency,
    String? domain,
  }) {
    return Product(
      id: id,
      url: url,
      title: title,
      price: price ?? this.price,
      availability: availability ?? this.availability,
      lastChecked: lastChecked ?? this.lastChecked,
      isAvailable: isAvailable ?? this.isAvailable,
      trackAvailability: trackAvailability ?? this.trackAvailability,
      trackPrice: trackPrice ?? this.trackPrice,
      initialPrice: initialPrice ?? this.initialPrice,
      priceHistory: priceHistory ?? this.priceHistory,
      imageUrl: imageUrl ?? this.imageUrl,
      currency: currency ?? this.currency,
      domain: domain ?? this.domain,
    );
  }
}

class PriceHistory {
  final DateTime date;
  final String price;
  final bool wasAvailable;

  PriceHistory({
    required this.date,
    required this.price,
    this.wasAvailable = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'price': price,
      'wasAvailable': wasAvailable,
    };
  }

  factory PriceHistory.fromJson(Map<String, dynamic> json) {
    return PriceHistory(
      date: DateTime.parse(json['date']),
      price: json['price'],
      wasAvailable: json['wasAvailable'] ?? true,
    );
  }
}

class ProductMonitorHome extends StatefulWidget {
  @override
  _ProductMonitorHomeState createState() => _ProductMonitorHomeState();
}

class _ProductMonitorHomeState extends State<ProductMonitorHome> with SingleTickerProviderStateMixin {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  List<Product> products = [];
  Timer? monitoringTimer;
  String scraperApiKey = '';
  int checkInterval = 20; // minutes
  bool isMonitoring = false;
  bool isLoading = false;
  bool backgroundMonitoring = false;
  late TabController _tabController;
  late ConfettiController _confettiController;
  bool _showConfetti = false;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    initializeNotifications();
    requestPermissions();
    loadSettings();
    loadProducts();
  }

  @override
  void dispose() {
    monitoringTimer?.cancel();
    _tabController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> requestPermissions() async {
    await Permission.notification.request();
    await Permission.ignoreBatteryOptimizations.request();
  }

  Future<void> initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.payload != null) {
          await launchUrl(Uri.parse(response.payload!));
        }
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'product_monitor',
      'Product Monitor',
      description: 'Notifications for product availability',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      scraperApiKey = prefs.getString('scraperApiKey') ?? '';
      checkInterval = prefs.getInt('checkInterval') ?? 20;
      backgroundMonitoring = prefs.getBool('backgroundMonitoring') ?? false;
    });
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('scraperApiKey', scraperApiKey);
    await prefs.setInt('checkInterval', checkInterval);
    await prefs.setBool('backgroundMonitoring', backgroundMonitoring);
  }

  Future<void> loadProducts() async {
    setState(() {
      isLoading = true;
    });
    
    final prefs = await SharedPreferences.getInstance();
    final productsJson = prefs.getStringList('products') ?? [];
    
    setState(() {
      products = productsJson
          .map((json) => Product.fromJson(jsonDecode(json)))
          .toList();
      isLoading = false;
    });
  }

  Future<void> saveProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final productsJson = products
        .map((product) => jsonEncode(product.toJson()))
        .toList();
    await prefs.setStringList('products', productsJson);
  }

  Future<void> showNotification(String title, String body, {String? payload}) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'product_monitor',
      'Product Monitor',
      channelDescription: 'Notifications for product availability',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF6B46C1),
    );
    
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  Future<Product?> checkProductAvailability(String url) async {
  try {
    if (scraperApiKey.isEmpty) {
      throw Exception('API key not set');
    }

    final response = await http.get(
      Uri.parse('https://api.scraperapi.com').replace(queryParameters: {
        'api_key': scraperApiKey,
        'url': url,
        'country_code': 'in',
        'render': 'true',
      }),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ).timeout(Duration(seconds: 60));

    if (response.statusCode == 200) {
      final document = html_parser.parse(response.body);
      
      String title = "Product Not Found";
      String price = "Price Not Found";
      String availability = "In Stock";
      bool isAvailable = true;
      String? imageUrl;
      String currency = '₹';
      String domain = Uri.parse(url).host;

      // Enhanced price extraction function
      String? extractPrice() {
        // Try to find price using multiple strategies
        final pricePattern = RegExp(r'(\d+[\.,]?\d*[\.,]?\d*)');
        
        // Common price selectors across multiple sites
        List<String> priceSelectors = [
          // Amazon
          '.a-price-whole', 
          '.priceToPay span',
          '.a-offscreen',
          // Flipkart
          '._30jeq3',
          '._16Jk6d',
          // Myntra
          '.pdp-price',
          // Ajio
          '.prod-sp',
          // Generic
          '[itemprop="price"]',
          '.price',
          '.current-price',
          '.price-number',
          '.final-price'
        ];

        // Try each selector until we find a price
        for (var selector in priceSelectors) {
          final element = document.querySelector(selector);
          if (element != null) {
            String priceText = element.text.trim();
            
            // Try to extract numeric price from the text
            final match = pricePattern.firstMatch(priceText);
            if (match != null) {
              // Clean the price string
              String cleanPrice = match.group(1)!
                .replaceAll(',', '') // Remove thousands separators
                .replaceAll(RegExp(r'[^0-9.]'), ''); // Remove non-numeric except decimal point
              
              // Format as currency (assuming Indian Rupees)
              try {
                double priceValue = double.parse(cleanPrice);
                return priceValue.toStringAsFixed(2);
              } catch (e) {
                print('Error parsing price: $e');
              }
            }
          }
        }
        return null;
      }

      // Extract title
      title = document.querySelector('h1')?.text.trim() ?? 
             document.querySelector('#productTitle')?.text.trim() ??
             document.querySelector('.B_NuCI')?.text.trim() ??
             document.querySelector('.pdp-title')?.text.trim() ??
             document.querySelector('.prod-name')?.text.trim() ??
             title;

      // Extract price using our enhanced function
      price = extractPrice() ?? price;

      // Extract availability
      availability = document.querySelector('#availability')?.text.trim() ??
                   document.querySelector('._16FRp0')?.text.trim() ??
                   (document.querySelector('.size-buttons-unified-size') != null 
                       ? "Available" : "Out of Stock") ??
                   document.querySelector('.edd-pincode-msg-details')?.text.trim() ??
                   availability;

      // Extract image URL
      imageUrl = document.querySelector('#landingImage')?.attributes['src'] ??
                document.querySelector('._396cs4')?.attributes['src'] ??
                document.querySelector('.image-grid-image')?.attributes['src'] ??
                document.querySelector('.img-container img')?.attributes['src'] ??
                document.querySelector('img[itemprop="image"]')?.attributes['src'];

      // Determine currency based on domain or price format
      if (domain.contains('.in') || 
          price.contains('₹') || 
          url.contains('amazon.in') || 
          url.contains('flipkart.com')) {
        currency = '₹';
      } else if (price.contains('\$')) {
        currency = '\$';
      } else if (price.contains('€')) {
        currency = '€';
      } else if (price.contains('£')) {
        currency = '£';
      }

      // Determine availability
      isAvailable = !availability.toLowerCase().contains('out of stock') && 
                   !availability.toLowerCase().contains('unavailable') &&
                   !availability.toLowerCase().contains('sold out') &&
                   !availability.toLowerCase().contains('currently unavailable');

      return Product(
        id: url.hashCode.toString(),
        url: url,
        title: title,
        price: price,
        availability: availability,
        lastChecked: DateTime.now(),
        isAvailable: isAvailable,
        trackAvailability: true,
        trackPrice: false,
        initialPrice: price,
        imageUrl: imageUrl,
        currency: currency,
        domain: domain,
      );
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  } catch (e) {
    print('Error checking product: $e');
    return null;
  }
}

  void startMonitoring() {
    if (scraperApiKey.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('API Key Required'),
          content: Text('Please set your ScraperAPI key in settings to start monitoring.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showSettingsDialog();
              },
              child: Text('Settings'),
            ),
          ],
        ),
      );
      return;
    }

    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please add at least one product to monitor'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    // Start foreground monitoring
    monitoringTimer = Timer.periodic(
      Duration(minutes: checkInterval),
      (timer) async {
        await checkAllProducts();
      },
    );

    // Start background monitoring if enabled
    if (backgroundMonitoring) {
      startBackgroundService();
    }

    setState(() {
      isMonitoring = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Monitoring started - checking every $checkInterval minutes'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Future<void> startBackgroundService() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    
    if (!isRunning) {
      await service.startService();
    }
    
    // Send data to the background service
    service.invoke('setAsForeground');
    service.invoke('start_task', {
      'checkInterval': checkInterval,
    });
  }

  void stopMonitoring() {
    monitoringTimer?.cancel();
    stopBackgroundService();
    
    setState(() {
      isMonitoring = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Monitoring stopped'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Future<void> stopBackgroundService() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    
    if (isRunning) {
      service.invoke('stopService');
    }
  }

  Future<void> checkAllProducts() async {
    bool hasAvailabilityChanges = false;
    bool hasPriceChanges = false;
    
    for (int i = 0; i < products.length; i++) {
      try {
        Product? updatedProduct = await checkProductAvailability(products[i].url);
        if (updatedProduct != null) {
          bool shouldNotify = false;
          String notificationTitle = '';
          String notificationBody = '';
          Product productToUpdate = updatedProduct.copyWith(
            trackAvailability: products[i].trackAvailability,
            trackPrice: products[i].trackPrice,
            initialPrice: products[i].initialPrice.isEmpty ? updatedProduct.price : products[i].initialPrice,
            priceHistory: products[i].priceHistory,
          );

          // Check for availability changes if tracking is enabled
          if (products[i].trackAvailability) {
            final wasUnavailable = !products[i].isAvailable;
            final isNowAvailable = updatedProduct.isAvailable;

            if (wasUnavailable && isNowAvailable) {
              shouldNotify = true;
              hasAvailabilityChanges = true;
              notificationTitle = '🎉 Product Available!';
              notificationBody = '${updatedProduct.title} is now in stock!';
            }
          }

          // Check for price changes if tracking is enabled
          if (products[i].trackPrice) {
            final oldPrice = products[i].price;
            final newPrice = updatedProduct.price;
            final initialPrice = products[i].initialPrice.isEmpty ? newPrice : products[i].initialPrice;

            if (oldPrice != newPrice) {
              shouldNotify = true;
              hasPriceChanges = true;
              notificationTitle = '💰 Price Changed!';
              notificationBody = '${updatedProduct.title} price changed from $oldPrice to $newPrice';

              // Update price history
              final newPriceHistory = List<PriceHistory>.from(products[i].priceHistory)
                ..add(PriceHistory(
                  date: DateTime.now(),
                  price: newPrice,
                  wasAvailable: updatedProduct.isAvailable,
                ));

              productToUpdate = productToUpdate.copyWith(
                priceHistory: newPriceHistory,
                initialPrice: initialPrice,
              );
            }
          }

          setState(() {
            products[i] = productToUpdate.copyWith(
              lastChecked: DateTime.now(),
            );
          });

          if (shouldNotify) {
            await showNotification(
              notificationTitle,
              notificationBody,
              payload: updatedProduct.url,
            );
          }
        }
        
        // Add delay between requests
        await Future.delayed(Duration(seconds: 5));
      } catch (e) {
        print('Error checking product ${products[i].title}: $e');
      }
    }
    
    await saveProducts();
    
    // Show confetti if there were positive changes
    if (hasAvailabilityChanges || hasPriceChanges) {
      setState(() {
        _showConfetti = true;
      });
      _confettiController.play();
      Future.delayed(Duration(seconds: 5), () {
        setState(() {
          _showConfetti = false;
        });
      });
    }
  }

  Future<void> checkSingleProduct(int index) async {
    setState(() {
      isLoading = true;
    });

    try {
      final updatedProduct = await checkProductAvailability(products[index].url);
      if (updatedProduct != null) {
        setState(() {
          products[index] = updatedProduct.copyWith(
            trackAvailability: products[index].trackAvailability,
            trackPrice: products[index].trackPrice,
            initialPrice: products[index].initialPrice.isEmpty ? updatedProduct.price : products[index].initialPrice,
            priceHistory: products[index].priceHistory,
          );
        });
        await saveProducts();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product updated successfully'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update product: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<void> addProduct(String url, {bool trackAvailability = true, bool trackPrice = false}) async {
    if (url.isEmpty) return;

    setState(() {
      isLoading = true;
    });

    try {
      final product = await checkProductAvailability(url);
      if (product != null) {
        setState(() {
          products.add(Product(
            id: product.id,
            url: product.url,
            title: product.title,
            price: product.price,
            availability: product.availability,
            lastChecked: product.lastChecked,
            isAvailable: product.isAvailable,
            trackAvailability: trackAvailability,
            trackPrice: trackPrice,
            initialPrice: product.price,
            priceHistory: [],
            imageUrl: product.imageUrl,
            currency: product.currency,
            domain: product.domain,
          ));
        });
        await saveProducts();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product added successfully'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add product: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    setState(() {
      isLoading = false;
    });
  }

  void updateProductTracking(int index, bool trackAvailability, bool trackPrice) async {
    setState(() {
      products[index] = products[index].copyWith(
        trackAvailability: trackAvailability,
        trackPrice: trackPrice,
      );
    });
    await saveProducts();
  }

  void removeProduct(String id) {
    setState(() {
      products.removeWhere((product) => product.id == id);
    });
    saveProducts();
  }

  void _showTrackingOptionsDialog(int index) {
    bool trackAvailability = products[index].trackAvailability;
    bool trackPrice = products[index].trackPrice;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Tracking Options'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: Text('Track Availability'),
                  value: trackAvailability,
                  onChanged: (value) {
                    setState(() {
                      trackAvailability = value;
                    });
                  },
                  activeColor: Color(0xFF6B46C1),
                ),
                SwitchListTile(
                  title: Text('Track Price Changes'),
                  value: trackPrice,
                  onChanged: (value) {
                    setState(() {
                      trackPrice = value;
                    });
                  },
                  activeColor: Color(0xFF6B46C1),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () {
                  updateProductTracking(index, trackAvailability, trackPrice);
                  Navigator.of(context).pop();
                },
                child: Text('Save', style: TextStyle(color: Color(0xFF6B46C1))),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPriceHistoryDialog(int index) {
    final product = products[index];
    final priceHistory = product.priceHistory;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Price History',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6B46C1),
                ),
              ),
            ),
            Divider(height: 0),
            Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              width: double.maxFinite,
              child: priceHistory.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history, size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No price history available',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: priceHistory.length,
                      itemBuilder: (context, i) {
                        final history = priceHistory[i];
                        return ListTile(
                          title: Text(
                            '${product.currency}${history.price}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: history.wasAvailable ? Colors.black : Colors.grey),
                          ),
                          subtitle: Text(
                            DateFormat('MMM dd, yyyy - HH:mm').format(history.date),
                            style: TextStyle(
                              color: history.wasAvailable ? Colors.grey : Colors.red),
                          ),
                          leading: Icon(
                            Icons.circle,
                            size: 12,
                            color: history.wasAvailable ? Colors.green : Colors.red,
                          ),
                          trailing: i == 0
                              ? badges.Badge(
                                  badgeStyle: badges.BadgeStyle(
                                    badgeColor: Color(0xFF6B46C1),
                                  ),
                                  badgeContent: Text(
                                    'Current',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10),
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
            ),
            Divider(height: 0),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close', style: TextStyle(color: Color(0xFF6B46C1))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProductDetails(int index) {
    final product = products[index];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          children: [
            Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                color: Colors.grey[100],
              ),
              child: Stack(
                children: [
                  if (product.imageUrl != null)
                    Center(
                      child: Image.network(
                        product.imageUrl!,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded / 
                                    loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.shopping_bag,
                          size: 100,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Icon(
                        Icons.shopping_bag,
                        size: 100,
                        color: Colors.grey,
                      ),
                    ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: product.isAvailable ? Colors.green : Colors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        product.isAvailable ? 'Available' : 'Out of Stock',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${product.currency}${_formatPrice(product.price)}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6B46C1)),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.open_in_new),
                        onPressed: () => launchUrl(Uri.parse(product.url)),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.store, size: 20, color: Colors.grey),
                      SizedBox(width: 8),
                      Text(
                        product.domain.replaceAll('www.', ''),
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 20, color: Colors.grey),
                      SizedBox(width: 8),
                      Text(
                        'Last checked: ${DateFormat('MMM dd, yyyy - HH:mm').format(product.lastChecked)}',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  if (product.trackPrice && product.priceHistory.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Price History',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Container(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: product.priceHistory.length,
                            itemBuilder: (context, i) {
                              final history = product.priceHistory[i];
                              return Container(
                                width: 120,
                                margin: EdgeInsets.only(right: 8),
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[200]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${product.currency}${history.price}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: history.wasAvailable 
                                            ? Colors.black 
                                            : Colors.grey),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      DateFormat('MMM dd').format(history.date),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: history.wasAvailable 
                                            ? Colors.grey 
                                            : Colors.red),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(String price) {
    try {
      // Remove all non-numeric characters except decimal point
      String cleaned = price.replaceAll(RegExp(r'[^0-9.]'), '');
      double value = double.parse(cleaned);
      return value.toStringAsFixed(2);
    } catch (e) {
      return price; // Return original if parsing fails
    }
  }

  void _confirmDeleteProduct(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Product'),
        content: Text('Are you sure you want to remove this product from your tracking list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              removeProduct(products[index].id);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Product removed'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
            child: Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddProductDialog() {
    final TextEditingController urlController = TextEditingController();
    bool trackAvailability = true;
    bool trackPrice = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Add Product',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: urlController,
                    decoration: InputDecoration(
                      labelText: 'Product URL',
                      hintText: 'Enter product URL from any shopping site',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                    maxLines: 3,
                  ),
                  SizedBox(height: 16),
                  SwitchListTile(
                    title: Text('Track Availability'),
                    value: trackAvailability,
                    onChanged: (value) {
                      setState(() {
                        trackAvailability = value;
                      });
                    },
                    activeColor: Color(0xFF6B46C1),
                  ),
                  SwitchListTile(
                    title: Text('Track Price Changes'),
                    value: trackPrice,
                    onChanged: (value) {
                      setState(() {
                        trackPrice = value;
                      });
                    },
                    activeColor: Color(0xFF6B46C1),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Supported sites: Amazon, Flipkart, Myntra, Ajio and more',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey),
                  ),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Cancel', style: TextStyle(color: Colors.grey)),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          addProduct(
                            urlController.text.trim(),
                            trackAvailability: trackAvailability,
                            trackPrice: trackPrice,
                          );
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF6B46C1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text('Add Product'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSettingsDialog() {
    final TextEditingController apiKeyController = 
        TextEditingController(text: scraperApiKey);
    final TextEditingController intervalController = 
        TextEditingController(text: checkInterval.toString());
    bool tempBackgroundMonitoring = backgroundMonitoring;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: apiKeyController,
                  decoration: InputDecoration(
                    labelText: 'ScraperAPI Key',
                    hintText: 'Enter your ScraperAPI key',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.key),
                  ),
                  obscureText: true,
                ),
                SizedBox(height: 16),
                TextField(
                  controller: intervalController,
                  decoration: InputDecoration(
                    labelText: 'Check Interval (minutes)',
                    hintText: 'Enter check interval in minutes',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.timer),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                SizedBox(height: 16),
                SwitchListTile(
                  title: Text('Background Monitoring'),
                  subtitle: Text('Keep monitoring when app is closed'),
                  value: tempBackgroundMonitoring,
                  onChanged: (value) {
                    setDialogState(() {
                      tempBackgroundMonitoring = value;
                    });
                  },
                  activeColor: Color(0xFF6B46C1),
                ),
                SizedBox(height: 8),
                Text(
                  'Minimum recommended interval: 15 minutes',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: Colors.grey)),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          scraperApiKey = apiKeyController.text.trim();
                          int newInterval = int.tryParse(intervalController.text) ?? 20;
                          checkInterval = newInterval < 1 ? 1 : newInterval;
                          backgroundMonitoring = tempBackgroundMonitoring;
                        });
                        saveSettings();
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF6B46C1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text('Save Settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'NK',
                style: TextStyle(
                  color: Color(0xFF6B46C1),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            SizedBox(width: 8),
            Text('Product Tracker'),
          ],
        ),
        actions: [
          IconButton(
            icon: badges.Badge(
              showBadge: products.any((p) => !p.isAvailable && p.trackAvailability),
              badgeStyle: badges.BadgeStyle(
                badgeColor: Colors.red,
              ),
              child: Icon(Icons.notifications_active),
            ),
            onPressed: isLoading ? null : () async {
              await checkAllProducts();
            },
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                margin: EdgeInsets.all(16),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6B46C1), Color(0xFF9F7AEA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.2),
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Product Tracker',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                              ),
                              SizedBox(height: 8),
                              Text(
                                isMonitoring 
                                    ? 'Active - Checking every $checkInterval min' 
                                    : 'Monitoring is stopped',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: isMonitoring ? stopMonitoring : startMonitoring,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Color(0xFF6B46C1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(isMonitoring ? Icons.stop : Icons.play_arrow, size: 20),
                              SizedBox(width: 4),
                              Text(isMonitoring ? 'Stop' : 'Start'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (backgroundMonitoring) ...[
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.cloud_sync, size: 16, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Background monitoring enabled',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (isLoading)
                LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: Color(0xFF6B46C1),
                ),
              Expanded(
                child: products.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Lottie.asset(
                              'assets/shopping.json',
                              width: 200,
                              height: 200,
                              fit: BoxFit.contain,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No products added yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Tap the + button to add a product',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await checkAllProducts();
                        },
                        color: Color(0xFF6B46C1),
                        child: ListView.builder(
                          physics: AlwaysScrollableScrollPhysics(),
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final product = products[index];
                            return Dismissible(
                              key: Key(product.id),
                              background: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: EdgeInsets.only(right: 20),
                                child: Icon(Icons.delete, color: Colors.white),
                              ),
                              confirmDismiss: (direction) async {
                                return await showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('Remove Product'),
                                    content: Text('Are you sure you want to remove this product from your tracking list?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        child: Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(true),
                                        child: Text('Remove', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              onDismissed: (direction) {
                                removeProduct(product.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Product removed'),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                );
                              },
                              child: GestureDetector(
                                onTap: () => _showProductDetails(index),
                                child: AnimatedContainer(
                                  duration: Duration(milliseconds: 300),
                                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Card(
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 80,
                                            height: 80,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              color: Colors.grey[100],
                                            ),
                                            child: product.imageUrl != null
                                                ? ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Image.network(
                                                      product.imageUrl!,
                                                      fit: BoxFit.contain,
                                                      loadingBuilder: (context, child, loadingProgress) {
                                                        if (loadingProgress == null) return child;
                                                        return Center(
                                                          child: CircularProgressIndicator(
                                                            value: loadingProgress.expectedTotalBytes != null
                                                                ? loadingProgress.cumulativeBytesLoaded / 
                                                                  loadingProgress.expectedTotalBytes!
                                                                : null,
                                                          ),
                                                        );
                                                      },
                                                      errorBuilder: (context, error, stackTrace) => Icon(
                                                        Icons.shopping_bag,
                                                        size: 40,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  )
                                                : Center(
                                                    child: Icon(
                                                      Icons.shopping_bag,
                                                      size: 40,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                          ),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        product.title,
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: Icon(Icons.delete, color: Colors.grey),
                                                      onPressed: () => _confirmDeleteProduct(index),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  '${product.currency}${_formatPrice(product.price)}',
                                                  style: TextStyle(
                                                    color: Color(0xFF6B46C1),
                                                    fontWeight: FontWeight.bold),
                                                ),
                                                SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: product.isAvailable 
                                                            ? Colors.green.withOpacity(0.1) 
                                                            : Colors.red.withOpacity(0.1),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        product.isAvailable ? 'In Stock' : 'Out of Stock',
                                                        style: TextStyle(
                                                          color: product.isAvailable ? Colors.green : Colors.red,
                                                          fontSize: 12),
                                                      ),
                                                    ),
                                                    Spacer(),
                                                    Text(
                                                      DateFormat('HH:mm').format(product.lastChecked),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
          if (_showConfetti)
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                colors: const [
                  Colors.green,
                  Colors.blue,
                  Colors.pink,
                  Colors.orange,
                  Colors.purple
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddProductDialog,
        child: Icon(Icons.add),
        tooltip: 'Add Product',
      ),
    );
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialize notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: initializationSettingsAndroid),
  );

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    service.on('start_task').listen((event) async {
      final checkInterval = event?['checkInterval'] ?? 20;
      
      while (true) {
        if (service is AndroidServiceInstance) {
          final androidService = service as AndroidServiceInstance;
          if (await androidService.isForegroundService() == false) {
            break;
          }
        }
        
        try {
          final prefs = await SharedPreferences.getInstance();
          final apiKey = prefs.getString('scraperApiKey') ?? '';
          final productsJson = prefs.getStringList('products') ?? [];
          
          if (apiKey.isEmpty || productsJson.isEmpty) {
            await Future.delayed(Duration(minutes: checkInterval));
            continue;
          }

          List<Product> products = productsJson
              .map((json) => Product.fromJson(jsonDecode(json)))
              .toList();

          bool hasUpdates = false;
          for (int i = 0; i < products.length; i++) {
            final updatedProduct = await _checkProductInBackground(products[i].url, apiKey);
            if (updatedProduct != null) {
              bool shouldNotify = false;
              String notificationTitle = '';
              String notificationBody = '';

              Product productToUpdate = updatedProduct.copyWith(
                trackAvailability: products[i].trackAvailability,
                trackPrice: products[i].trackPrice,
                initialPrice: products[i].initialPrice.isEmpty ? updatedProduct.price : products[i].initialPrice,
                priceHistory: products[i].priceHistory,
              );

              if (products[i].trackAvailability) {
                final wasUnavailable = !products[i].isAvailable;
                final isNowAvailable = updatedProduct.isAvailable;

                if (wasUnavailable && isNowAvailable) {
                  shouldNotify = true;
                  notificationTitle = '🎉 Product Available!';
                  notificationBody = '${updatedProduct.title} is now in stock!';
                }
              }

              if (products[i].trackPrice) {
                final oldPrice = products[i].price;
                final newPrice = updatedProduct.price;
                final initialPrice = products[i].initialPrice.isEmpty ? newPrice : products[i].initialPrice;

                if (oldPrice != newPrice) {
                  shouldNotify = true;
                  notificationTitle = '💰 Price Changed!';
                  notificationBody = '${updatedProduct.title} price changed from $oldPrice to $newPrice';

                  final newPriceHistory = List<PriceHistory>.from(products[i].priceHistory)
                    ..add(PriceHistory(
                      date: DateTime.now(),
                      price: newPrice,
                      wasAvailable: updatedProduct.isAvailable,
                    ));

                  productToUpdate = productToUpdate.copyWith(
                    priceHistory: newPriceHistory,
                    initialPrice: initialPrice,
                  );
                }
              }

              products[i] = productToUpdate.copyWith(
                lastChecked: DateTime.now(),
              );
              hasUpdates = true;

              if (shouldNotify) {
                await _showBackgroundNotification(
                  flutterLocalNotificationsPlugin,
                  notificationTitle,
                  notificationBody,
                  updatedProduct.url,
                );
              }
            }
            
            await Future.delayed(Duration(seconds: 5));
          }

          if (hasUpdates) {
            final updatedProductsJson = products
                .map((product) => jsonEncode(product.toJson()))
                .toList();
            await prefs.setStringList('products', updatedProductsJson);
          }

          await Future.delayed(Duration(minutes: checkInterval));
        } catch (e) {
          print("Background task error: $e");
          await Future.delayed(Duration(minutes: 5));
        }
      }
    });
  }
}

Future<Product?> _checkProductInBackground(String url, String apiKey) async {
  try {
    final response = await http.get(
      Uri.parse('https://api.scraperapi.com').replace(queryParameters: {
        'api_key': apiKey,
        'url': url,
        'country_code': 'in',
        'render': 'true',
      }),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ).timeout(Duration(seconds: 60));

    if (response.statusCode == 200) {
      final document = html_parser.parse(response.body);
      
      String title = "Product Not Found";
      String price = "Price Not Found";
      String availability = "In Stock";
      bool isAvailable = true;
      String domain = Uri.parse(url).host;

      // Amazon specific extraction
      if (domain.contains('amazon.')) {
        title = document.querySelector('#productTitle')?.text.trim() ?? title;
        price = document.querySelector('.a-price-whole')?.text.trim() ?? 
                document.querySelector('.priceToPay span')?.text.trim() ??
                document.querySelector('.a-offscreen')?.text.trim() ??
                price;
        // Clean price string
        price = price.replaceAll(RegExp(r'[^0-9.]'), '');
        availability = document.querySelector('#availability')?.text.trim() ?? availability;
      } 
      // Flipkart specific extraction
      else if (domain.contains('flipkart.com')) {
        title = document.querySelector('.B_NuCI')?.text.trim() ?? title;
        price = document.querySelector('._30jeq3')?.text.trim() ?? 
                document.querySelector('._16Jk6d')?.text.trim() ??
                price;
        // Clean price string
        price = price.replaceAll(RegExp(r'[^0-9.]'), '');
        availability = document.querySelector('._16FRp0')?.text.trim() ?? "Available";
      }
      // Generic extraction as fallback
      else {
        title = document.querySelector('h1')?.text.trim() ?? title;
        price = document.querySelector('[itemprop="price"]')?.text.trim() ?? price;
        availability = document.querySelector('[itemprop="availability"]')?.text.trim() ?? availability;
      }

      isAvailable = !availability.toLowerCase().contains('out of stock') && 
                   !availability.toLowerCase().contains('unavailable') &&
                   !availability.toLowerCase().contains('sold out');

      return Product(
        id: url.hashCode.toString(),
        url: url,
        title: title,
        price: price,
        availability: availability,
        lastChecked: DateTime.now(),
        isAvailable: isAvailable,
        trackAvailability: true,
        trackPrice: false,
        initialPrice: price,
        domain: domain,
      );
    }
  } catch (e) {
    print('Error checking product in background: $e');
  }
  return null;
}

Future<void> _showBackgroundNotification(
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
  String title, 
  String body,
  String url,
) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'product_monitor_bg',
    'Product Monitor Background',
    channelDescription: 'Background notifications for product availability',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    playSound: true,
    icon: '@mipmap/ic_launcher',
    color: Color(0xFF6B46C1),
  );
  
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
  
  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    platformChannelSpecifics,
    payload: url,
  );
}