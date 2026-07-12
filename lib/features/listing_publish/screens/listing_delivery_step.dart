import 'package:flutter/material.dart';

import '../../../core/app_typography.dart';
import '../data/listing_catalogs.dart';
import '../listing_publish_controller.dart';

class ListingDeliveryStep extends StatefulWidget {
  const ListingDeliveryStep({super.key, required this.controller});

  final ListingPublishController controller;

  @override
  State<ListingDeliveryStep> createState() => _ListingDeliveryStepState();
}

class _ListingDeliveryStepState extends State<ListingDeliveryStep> {
  late final TextEditingController _city;
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    _city = TextEditingController(text: widget.controller.draft.city);
    _address = TextEditingController(
      text: widget.controller.draft.shippingAddress,
    );
  }

  @override
  void didUpdateWidget(covariant ListingDeliveryStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    final draft = widget.controller.draft;
    if (!_city.selection.isValid && _city.text != draft.city) {
      _city.text = draft.city;
    }
    if (!_address.selection.isValid && _address.text != draft.shippingAddress) {
      _address.text = draft.shippingAddress;
    }
  }

  @override
  void dispose() {
    _city.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final draft = controller.draft;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const Text(
          'Откуда отправлять вещь?',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 16,
            fontWeight: AppTypography.semiBold,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Адрес видите только вы. Покупателю показывается город.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: AppTypography.medium,
            height: 1.35,
            letterSpacing: 0,
            color: Color(0xFF8F8F94),
          ),
        ),
        if (controller.savedAddresses.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'Сохранённые адреса',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              fontWeight: AppTypography.semiBold,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          ...controller.savedAddresses.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  controller.selectAddress(item);
                  setState(() {
                    _city.text = item.city;
                    _address.text = item.address;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: draft.shippingAddressId == item.id
                        ? const Color(0xFFF0F0F1)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE7E7EA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 12.5,
                            fontWeight: AppTypography.medium,
                            height: 1.35,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      if (draft.shippingAddressId == item.id)
                        const Icon(Icons.check_circle, size: 19),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _TextFieldBlock(
          label: 'Город',
          isRequired: true,
          controller: _city,
          hint: 'Например, Москва',
          textInputAction: TextInputAction.next,
          onChanged: controller.setCity,
        ),
        const SizedBox(height: 16),
        _TextFieldBlock(
          label: 'Адрес отправки',
          isRequired: true,
          controller: _address,
          hint: 'Улица, дом, квартира',
          textInputAction: TextInputAction.done,
          onChanged: controller.setShippingAddress,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Сделать адресом по умолчанию',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: AppTypography.medium,
              letterSpacing: 0,
            ),
          ),
          value: draft.saveAddressAsDefault,
          activeTrackColor: Colors.black,
          onChanged: controller.setSaveAddressAsDefault,
        ),
        const SizedBox(height: 14),
        const Text.rich(
          TextSpan(
            text: 'Доставка и встреча',
            children: [
              TextSpan(
                text: ' *',
                style: TextStyle(
                  color: Color(0xFFE11D2E),
                  fontWeight: AppTypography.bold,
                ),
              ),
            ],
          ),
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 16,
            fontWeight: AppTypography.semiBold,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Можно отключить любой способ только для этого объявления.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: AppTypography.medium,
            letterSpacing: 0,
            color: Color(0xFF8F8F94),
          ),
        ),
        const SizedBox(height: 10),
        ...ListingCatalogs.deliveryMethods.map(
          (method) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.trailing,
            activeColor: Colors.black,
            title: Text(
              method.name,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                fontWeight: AppTypography.medium,
                letterSpacing: 0,
              ),
            ),
            value: draft.deliveryMethods.contains(method.id),
            onChanged: (_) => controller.toggleDeliveryMethod(method.id),
          ),
        ),
      ],
    );
  }
}

class _TextFieldBlock extends StatelessWidget {
  const _TextFieldBlock({
    required this.label,
    this.isRequired = false,
    required this.controller,
    required this.hint,
    required this.textInputAction,
    required this.onChanged,
  });

  final String label;
  final bool isRequired;
  final TextEditingController controller;
  final String hint;
  final TextInputAction textInputAction;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text.rich(
        TextSpan(
          text: label,
          children: [
            if (isRequired)
              const TextSpan(
                text: ' *',
                style: TextStyle(
                  color: Color(0xFFE11D2E),
                  fontWeight: AppTypography.bold,
                ),
              ),
          ],
        ),
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12.5,
          fontWeight: AppTypography.semiBold,
          letterSpacing: 0,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        textInputAction: textInputAction,
        onChanged: onChanged,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          fontWeight: AppTypography.medium,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontWeight: AppTypography.medium,
            color: Color(0xFF8F8F94),
            letterSpacing: 0,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE7E7EA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black),
          ),
        ),
      ),
    ],
  );
}
