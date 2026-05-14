import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/created_outfit.dart';
import 'screens/catalog_screen.dart';
import 'screens/create_outfit_screen.dart';
import 'screens/create_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/outfits_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/publish_outfit_screen.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/create_entry_sheet.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  if (kIsWeb) {
    runApp(
      DevicePreview(
        enabled: true,
        builder: (context) => const FashionApp(),
      ),
    );
  } else {
    runApp(const FashionApp());
  }
}

class FashionApp extends StatelessWidget {
  const FashionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fashion App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: '.SF Pro Text',
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF070707),
          surface: Colors.white,
        ),
      ),
      home: const AppShell(),
    );
  }
}

class FashionAppWithPreview extends StatelessWidget {
  const FashionAppWithPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return DevicePreview(
      enabled: true,
      builder: (context) => const FashionApp(),
    );
  }
}

enum _CreateMode { none, createOutfit, publishOutfit, createItem }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _sidePadding = 18.0;

  int _currentIndex = 0;
  _CreateMode _createMode = _CreateMode.none;
  final List<CreatedOutfit> _createdOutfits = [];

  void _changeTab(int index) {
    setState(() {
      _currentIndex = index;
      _createMode = _CreateMode.none;
    });
  }

  void _openCreateOutfit() {
    setState(() {
      _createMode = _CreateMode.createOutfit;
      _currentIndex = 2;
    });
  }

  void _openPublishOutfit() {
    setState(() {
      _createMode = _CreateMode.publishOutfit;
      _currentIndex = 2;
    });
  }

  void _openCreateItem() {
    setState(() {
      _createMode = _CreateMode.createItem;
      _currentIndex = 2;
    });
  }

  void _publishOutfit(CreatedOutfit outfit) {
    setState(() {
      _createdOutfits.insert(0, outfit);
      _currentIndex = 1;
      _createMode = _CreateMode.none;
    });
  }

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => CreateEntrySheet(
        onCreateOutfit: () {
          Navigator.pop(ctx);
          _openCreateOutfit();
        },
        onPublishOutfit: () {
          Navigator.pop(ctx);
          _openPublishOutfit();
        },
        onCreateItem: () {
          Navigator.pop(ctx);
          _openCreateItem();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _currentIndex,
          children: [
            CatalogScreen(scale: 1.0, sidePadding: _sidePadding),
            OutfitsScreen(
              scale: 1.0,
              sidePadding: _sidePadding,
              createdOutfits: _createdOutfits,
              onCreateTap: _openPublishOutfit,
            ),
            _buildCreateScreen(),
            const MessagesScreen(),
            const ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onTabSelected: _changeTab,
        onCreateTap: _showCreateSheet,
      ),
    );
  }

  Widget _buildCreateScreen() {
    switch (_createMode) {
      case _CreateMode.createOutfit:
        return CreateOutfitScreen(
          sidePadding: _sidePadding,
          onClose: () => _changeTab(0),
          onPublish: (_) {},
        );
      case _CreateMode.publishOutfit:
        return PublishOutfitScreen(
          sidePadding: _sidePadding,
          onClose: () => _changeTab(0),
          onPublish: _publishOutfit,
          onAddItem: () {
            setState(() => _createMode = _CreateMode.createItem);
          },
        );
      case _CreateMode.createItem:
        return CreateScreen(
          scale: 1.0,
          sidePadding: _sidePadding,
          onClose: () => _changeTab(0),
          onTabChange: _changeTab,
        );
      case _CreateMode.none:
        return const SizedBox();
    }
  }
}
