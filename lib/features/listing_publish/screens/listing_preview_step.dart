import 'package:flutter/material.dart';

import '../../../models/profile_feature.dart';
import '../../../screens/product_screen.dart';
import '../listing_publish_controller.dart';
import '../models/listing_draft.dart';

class ListingPreviewStep extends StatelessWidget {
  const ListingPreviewStep({super.key, required this.controller});

  final ListingPublishController controller;

  @override
  Widget build(BuildContext context) {
    final product = controller.buildProduct(preview: true);
    return Column(
      children: [
        Expanded(
          child: ProductScreen(
            isPreview: true,
            sourceProduct: product,
            product: ProductDetailData(
              id: product.id,
              title: product.title,
              description: product.description,
              price: product.price,
              priceValue: product.priceValue,
              image: product.image,
              images: product.images.isNotEmpty
                  ? product.images
                  : [product.image],
              category: product.category,
              brand: product.brand,
              color: product.color,
              sellerName: product.sellerName,
              sellerHandle: product.sellerHandle,
              size: product.size,
              condition: product.condition,
              location: product.location,
              isLiked: product.isLiked,
              shippingAddress: product.shippingAddress,
            ),
            onLike: () {},
            onContactSeller: () {},
            onOpenSeller: () {},
            onOpenReviews: () {},
            relatedProducts: const [],
            onRelatedProductTap: (_) {},
            deliveryProfile: DeliveryProfile(
              city: controller.draft.city,
              address: controller.draft.shippingAddress,
            ),
            onSaveDeliveryProfile: (_) async {},
            onCreateDeliveryOrder:
                ({required deliveryService, required deliveryPrice}) async =>
                    null,
          ),
        ),
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: Container(
            key: const Key('seller-declarations-panel'),
            constraints: const BoxConstraints(maxHeight: 270),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              children: [
                Text(
                  'Подтверждения продавца '
                  '(${controller.draft.sellerDeclarations.length}/'
                  '${SellerDeclaration.values.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                for (final declaration in SellerDeclaration.values)
                  CheckboxListTile(
                    key: Key('seller-declaration-${declaration.wireName}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: controller.draft.sellerDeclarations.contains(
                      declaration,
                    ),
                    title: Text(
                      declaration.label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onChanged: (value) => controller.setSellerDeclaration(
                      declaration,
                      value ?? false,
                    ),
                  ),
                Text(
                  'Версия: ${controller.draft.sellerConfirmationVersion}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
