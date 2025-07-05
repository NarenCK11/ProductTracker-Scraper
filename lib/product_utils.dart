import 'package:html/dom.dart';

class ProductUtils {
  static String? extractFlipkartTitle(Document document) {
    final selectors = [
      'span.B_NuCI',
      'h1.yhB1nd', 
      'h1._35KyD6',
      'span._35KyD6',
      'h1'
    ];
    
    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null && element.text!.trim().isNotEmpty) {
        return element.text!.trim();
      }
    }
    return null;
  }

  static String? extractFlipkartPrice(Document document) {
    final selectors = [
      'div._30jeq3._16Jk6d',
      'div._30jeq3',
      'div._1_WHN1',
      'div._3I9_wc._2p6lqe',
      'span._1_WHN1'
    ];
    
    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null && element.text!.trim().isNotEmpty) {
        return element.text!.trim();
      }
    }
    return null;
  }

  static String extractFlipkartAvailability(Document document) {
    final pageText = document.outerHtml.toLowerCase();
    final outOfStockIndicators = [
      'notify me', 'sold out', 'out of stock', 'currently unavailable',
      'temporarily unavailable', 'coming soon'
    ];
    
    for (final indicator in outOfStockIndicators) {
      if (pageText.contains(indicator)) {
        return 'Out of Stock';
      }
    }
    return 'In Stock';
  }

  static String? extractAmazonTitle(Document document) {
    final selectors = [
      '#productTitle',
      'h1.a-size-large',
      'h1 span'
    ];
    
    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null && element.text!.trim().isNotEmpty) {
        return element.text!.trim();
      }
    }
    return null;
  }

  static String? extractAmazonPrice(Document document) {
    final selectors = [
      '.a-price-whole',
      '.a-price .a-offscreen',
      '#priceblock_dealprice',
      '#priceblock_ourprice'
    ];
    
    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null && element.text!.trim().isNotEmpty) {
        return element.text!.trim();
      }
    }
    return null;
  }

  static String extractAmazonAvailability(Document document) {
    final selectors = [
      '#availability span',
      '#availability',
      '.a-color-state'
    ];
    
    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null) {
        final text = element.text!.toLowerCase();
        if (text.contains('out of stock') || text.contains('unavailable')) {
          return 'Out of Stock';
        }
      }
    }
    return 'In Stock';
  }
}