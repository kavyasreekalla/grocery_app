import 'package:flutter/material.dart';

class LanguageProvider extends ChangeNotifier {
  String _language = 'en';

  String get language => _language;

  void toggleLanguage() {
    if (_language == 'en') {
      _language = 'te';
    } else if (_language == 'te') {
      _language = 'hi';
    } else {
      _language = 'en';
    }
    notifyListeners();
  }

  String get languageLabel {
    switch (_language) {
      case 'en':
        return 'EN';
      case 'te':
        return 'TE';
      case 'hi':
        return 'HI';
      default:
        return 'EN';
    }
  }
}
