import 'package:flutter/material.dart';

import '../../../models/profile_feature.dart';
import '../../../screens/product_screen.dart';
import '../listing_publish_controller.dart';

class ListingPreviewStep extends StatelessWidget {
  const ListingPreviewStep({super.key, required this.controller});

  final ListingPublishController controller;

  @override
  Widget build(BuildContext context) {
    final product = controller.buildProduct(preview: true);
    return ProductScreen(
      isPreview: true,
      sourceProduct: product,
      product: ProductDetailData(
        id: product.id,
        title: product.title,
        description: product.description,
        price: product.price,
        priceValue: product.priceValue,
        image: product.image,
        images: product.images.isNotEmpty ? product.images : [product.image],
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
      onAddToCart: () {},
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
          ({required deliveryService, required deliveryPrice}) async => null,
    );
  }
}
