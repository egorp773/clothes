import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_typography.dart';
import 'core/supabase_config.dart';
import 'data/app_repository.dart';
import 'models/created_outfit.dart';
import 'models/product.dart';
import 'screens/catalog_screen.dart';
import 'screens/create_screen.dart';
import 'screens/login_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/outfit_create_screen.dart';
import 'screens/outfits_screen.dart';
import 'screens/outfit_only_item_screen.dart';
import 'screens/phone_login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/publish_outfit_screen.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/create_entry_sheet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
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
      DevicePreview(enabled: true, builder: (context) => const FashionApp()),
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
        fontFamily: 'Montserrat',
        textTheme: _montserratMediumTextTheme(ThemeData.light().textTheme),
        primaryTextTheme: _montserratMediumTextTheme(
          ThemeData.light().primaryTextTheme,
        ),
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

TextTheme _montserratMediumTextTheme(TextTheme base) {
  TextStyle? medium(TextStyle? style) => style?.copyWith(
    fontFamily: AppTypography.fontFamily,
    fontWeight: AppTypography.medium,
    letterSpacing: 0,
  );

  return base.copyWith(
    displayLarge: medium(base.displayLarge),
    displayMedium: medium(base.displayMedium),
    displaySmall: medium(base.displaySmall),
    headlineLarge: medium(base.headlineLarge),
    headlineMedium: medium(base.headlineMedium),
    headlineSmall: medium(base.headlineSmall),
    titleLarge: medium(base.titleLarge),
    titleMedium: medium(base.titleMedium),
    titleSmall: medium(base.titleSmall),
    bodyLarge: medium(base.bodyLarge),
    bodyMedium: medium(base.bodyMedium),
    bodySmall: medium(base.bodySmall),
    labelLarge: medium(base.labelLarge),
    labelMedium: medium(base.labelMedium),
    labelSmall: medium(base.labelSmall),
  );
}

enum _CreateMode {
  none,
  createOutfit,
  publishOutfit,
  createItem,
  outfitOnlyItem,
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _sidePadding = 18.0;

  int _currentIndex = 0;
  _CreateMode _createMode = _CreateMode.none;
  bool _returnToPublishOutfitAfterItem = false;
  bool _createItemForOutfitOnly = false;
  final List<Product> _draftOutfitProducts = [];
  final AppRepository _repository = AppRepository();

  @override
  void initState() {
    super.initState();
    _repository.load();
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  void _changeTab(int index) {
    if (!_repository.isSignedIn && (index == 3 || index == 4)) {
      _openLoginScreen(onSignedIn: () => _changeTab(index));
      return;
    }
    setState(() {
      _currentIndex = index;
      _createMode = _CreateMode.none;
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
  }

  void _openCreateOutfit() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => OutfitCreateScreen(
          myProducts: _repository.myProducts,
          likedProducts: _repository.products
              .where((product) => product.isLiked && !product.isHidden)
              .toList(),
          defaultAccessories: _repository.defaultAccessories,
          myAccessories: _repository.myAccessories,
          authorName: _repository.profile.name,
          authorHandle: _repository.profile.handle,
          onPublish: (outfit) =>
              _publishOutfitFromCreateRoute(routeContext, outfit),
          onCreateAccessory:
              (imageFile, {required bool isDefault, required String title}) {
                return _repository.createOutfitAccessory(
                  imageFile: imageFile,
                  isDefault: isDefault,
                  title: title,
                );
              },
        ),
      ),
    );
  }

  void _openPublishOutfit() {
    if (!_repository.isSignedIn) {
      _openLoginScreen(onSignedIn: _openPublishOutfit);
      return;
    }
    setState(() {
      _createMode = _CreateMode.publishOutfit;
      _currentIndex = 2;
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
  }

  void _openCreateItem() {
    if (!_repository.isSignedIn) {
      _openLoginScreen(onSignedIn: _openCreateItem);
      return;
    }
    setState(() {
      _createMode = _CreateMode.createItem;
      _currentIndex = 2;
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
  }

  Future<void> _publishOutfit(CreatedOutfit outfit) async {
    await _repository.publishOutfit(outfit);
    setState(() {
      _currentIndex = 1;
      _createMode = _CreateMode.none;
      _draftOutfitProducts.clear();
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
  }

  Future<void> _publishOutfitFromCreateRoute(
    BuildContext routeContext,
    CreatedOutfit outfit,
  ) async {
    final navigator = Navigator.of(routeContext, rootNavigator: true);
    await _repository.publishOutfit(outfit);
    if (!mounted) return;
    navigator.popUntil((route) => route.isFirst);
    setState(() {
      _currentIndex = 1;
      _createMode = _CreateMode.none;
      _draftOutfitProducts.clear();
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
  }

  Future<bool> _publishProduct(Product product) async {
    final didPublish = await _repository.publishProduct(product);
    if (didPublish) {
      setState(() {
        if (_returnToPublishOutfitAfterItem) {
          _currentIndex = 2;
          _createMode = _CreateMode.publishOutfit;
        } else {
          _currentIndex = 0;
          _createMode = _CreateMode.none;
        }
        _returnToPublishOutfitAfterItem = false;
        _createItemForOutfitOnly = false;
      });
    }
    return didPublish;
  }

  Future<bool> _addProductToOutfitOnly(Product product) async {
    final draftProduct = product.isHidden
        ? product
        : product.copyWith(isHidden: true);
    await _repository.publishProduct(draftProduct);
    setState(() {
      _draftOutfitProducts.insert(0, draftProduct);
      _currentIndex = 2;
      _createMode = _CreateMode.publishOutfit;
      _returnToPublishOutfitAfterItem = false;
      _createItemForOutfitOnly = false;
    });
    return true;
  }

  Future<void> _addOutfitOnlyProduct(Product product) async {
    await _addProductToOutfitOnly(product);
  }

  void _closeCreateItem() {
    if (_returnToPublishOutfitAfterItem || _createItemForOutfitOnly) {
      setState(() {
        _currentIndex = 2;
        _createMode = _CreateMode.publishOutfit;
        _returnToPublishOutfitAfterItem = false;
        _createItemForOutfitOnly = false;
      });
      return;
    }
    _changeTab(0);
  }

  void _showCreateSheet() {
    if (!_repository.isSignedIn) {
      _openLoginScreen(onSignedIn: _showCreateSheet);
      return;
    }
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

  void _showOutfitItemChoiceSheet() {
    if (!_repository.isSignedIn) {
      _openLoginScreen(onSignedIn: _showOutfitItemChoiceSheet);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      isScrollControlled: true,
      useSafeArea: false,
      builder: (ctx) => _OutfitItemChoiceSheet(
        onPublishItem: () {
          Navigator.pop(ctx);
          setState(() {
            _returnToPublishOutfitAfterItem = true;
            _createItemForOutfitOnly = false;
            _createMode = _CreateMode.createItem;
            _currentIndex = 2;
          });
        },
        onOutfitOnlyItem: () {
          Navigator.pop(ctx);
          setState(() {
            _returnToPublishOutfitAfterItem = true;
            _createItemForOutfitOnly = true;
            _createMode = _CreateMode.outfitOnlyItem;
            _currentIndex = 2;
          });
        },
      ),
    );
  }

  void _openLoginScreen({VoidCallback? onSignedIn}) {
    var didComplete = false;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (loginContext) => AnimatedBuilder(
          animation: _repository,
          builder: (context, _) {
            if (_repository.isSignedIn && !didComplete) {
              didComplete = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(loginContext).canPop()) {
                  Navigator.of(loginContext).pop();
                }
                onSignedIn?.call();
              });
            }
            return LoginScreen(
              onClose: () => Navigator.of(loginContext).pop(),
              onYandexTap: () {
                _repository.signInWithYandex();
              },
              onVkTap: () {
                _repository.signInWithVk();
              },
              onPhoneTap: () {
                Navigator.of(loginContext).push(
                  MaterialPageRoute<void>(
                    builder: (phoneContext) => PhoneLoginScreen(
                      onBack: () => Navigator.of(phoneContext).pop(),
                      onClose: () {
                        final navigator = Navigator.of(phoneContext);
                        navigator.pop();
                        if (navigator.canPop()) {
                          navigator.pop();
                        }
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _repository,
      builder: (context, _) {
        if (!_repository.isReady) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF070707),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: _currentIndex == 1
              ? const Color(0xFFF4F4F4)
              : Colors.white,
          body: SafeArea(
            top: false,
            bottom: false,
            child: IndexedStack(
              index: _currentIndex,
              children: [
                CatalogScreen(
                  scale: 1.0,
                  sidePadding: _sidePadding,
                  products: _repository.products,
                  onToggleLike: _repository.toggleProductLike,
                  onHideProduct: _repository.hideProduct,
                  onContactSeller: _repository.contactSeller,
                  onSendMessage: _repository.sendMessage,
                  currentUserId: _repository.currentUserId,
                  threadsListenable: _repository,
                  resolveThread: _repository.threadById,
                ),
                OutfitsScreen(
                  scale: 1.0,
                  sidePadding: _sidePadding,
                  createdOutfits: _repository.outfits,
                  products: _repository.products,
                  onCreateTap: _openPublishOutfit,
                ),
                _buildCreateScreen(),
                MessagesScreen(
                  threads: _repository.threads,
                  onSendMessage: _repository.sendMessage,
                  onSearchUsers: _repository.searchUserProfiles,
                  onStartDirectChat: _repository.startDirectChat,
                  currentUserId: _repository.currentUserId,
                  threadsListenable: _repository,
                  resolveThread: _repository.threadById,
                ),
                ProfileScreen(
                  profile: _repository.profile,
                  products: _repository.myProducts,
                  outfits: _repository.myOutfits,
                  isSignedIn: _repository.isSignedIn,
                  isSigningIn: _repository.isSigningIn,
                  accountLabel:
                      (_repository.currentUser?.email?.endsWith(
                            '@telegram.local',
                          ) ??
                          false)
                      ? _repository.profile.handle
                      : _repository.currentUser?.email,
                  authError: _repository.authError,
                  onSignInWithYandex: _repository.signInWithYandex,
                  onSignInWithTelegram: _repository.signInWithTelegram,
                  onSignOut: _repository.signOut,
                  onUpdateProfile: _repository.updateProfile,
                ),
              ],
            ),
          ),
          bottomNavigationBar: AppBottomNav(
            currentIndex: _currentIndex,
            onTabSelected: _changeTab,
            onCreateTap: _showCreateSheet,
          ),
        );
      },
    );
  }

  Widget _buildCreateScreen() {
    switch (_createMode) {
      case _CreateMode.createOutfit:
        return OutfitCreateScreen(
          onClose: () => _changeTab(0),
          myProducts: _repository.myProducts,
          likedProducts: _repository.products
              .where((product) => product.isLiked && !product.isHidden)
              .toList(),
          defaultAccessories: _repository.defaultAccessories,
          myAccessories: _repository.myAccessories,
          authorName: _repository.profile.name,
          authorHandle: _repository.profile.handle,
          onPublish: _publishOutfit,
          onCreateAccessory:
              (imageFile, {required bool isDefault, required String title}) {
                return _repository.createOutfitAccessory(
                  imageFile: imageFile,
                  isDefault: isDefault,
                  title: title,
                );
              },
        );
      case _CreateMode.publishOutfit:
        return _buildPublishOutfitScreen();
      case _CreateMode.createItem:
        return CreateScreen(
          scale: 1.0,
          sidePadding: _sidePadding,
          onClose: _closeCreateItem,
          onTabChange: _changeTab,
          onPublish: _createItemForOutfitOnly
              ? _addProductToOutfitOnly
              : _publishProduct,
          onUploadImage: _repository.uploadImage,
          publishButtonText: _createItemForOutfitOnly
              ? 'Добавить в образ'
              : 'Опубликовать вещь',
          successMessage: _createItemForOutfitOnly
              ? 'Вещь добавлена в образ'
              : 'Вещь опубликована',
          failureMessage: _createItemForOutfitOnly
              ? 'Не удалось добавить вещь в образ'
              : 'Не удалось сохранить вещь в базе',
        );
      case _CreateMode.outfitOnlyItem:
        return OutfitOnlyItemScreen(
          sidePadding: _sidePadding,
          onClose: _closeCreateItem,
          onAdd: _addOutfitOnlyProduct,
          onUploadImage: _repository.uploadImage,
        );
      case _CreateMode.none:
        return const SizedBox();
    }
  }

  Widget _buildPublishOutfitScreen() {
    return PublishOutfitScreen(
      sidePadding: _sidePadding,
      onClose: () => _changeTab(0),
      onPublish: _publishOutfit,
      products: [
        ..._draftOutfitProducts,
        ..._repository.products.where((product) => !product.isHidden),
      ],
      onUploadImage: _repository.uploadImage,
      onAddItem: _showOutfitItemChoiceSheet,
    );
  }
}

class _OutfitItemChoiceSheet extends StatelessWidget {
  const _OutfitItemChoiceSheet({
    required this.onPublishItem,
    required this.onOutfitOnlyItem,
  });

  final VoidCallback onPublishItem;
  final VoidCallback onOutfitOnlyItem;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E4),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          _OutfitItemChoiceTile(
            icon: Icons.storefront_outlined,
            title: 'Добавить для публикации',
            subtitle: 'Вещь появится в каталоге и будет доступна в образе',
            onTap: onPublishItem,
          ),
          const SizedBox(height: 10),
          _OutfitItemChoiceTile(
            icon: Icons.checkroom_outlined,
            title: 'Только для образа',
            subtitle: 'Вещь попадет только в текущий образ, без каталога',
            onTap: onOutfitOnlyItem,
          ),
        ],
      ),
    );
  }
}

class _OutfitItemChoiceTile extends StatelessWidget {
  const _OutfitItemChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEDEDF0)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 22, color: const Color(0xFF111111)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.15,
                      color: Color(0xFF8F8F94),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 22, color: Color(0xFFB8B8BE)),
          ],
        ),
      ),
    );
  }
}

class CreateOutfitComingSoonScreen extends StatelessWidget {
  const CreateOutfitComingSoonScreen({
    super.key,
    required this.sidePadding,
    required this.onClose,
  });

  final double sidePadding;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        sidePadding,
        topInset + 14,
        sidePadding,
        110,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                GestureDetector(
                  onTap: onClose,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.close,
                      size: 26,
                      color: Color(0xFF0B0B0B),
                    ),
                  ),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      'Создать образ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF0B0B0B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Будет доступно потом',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF111111),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
