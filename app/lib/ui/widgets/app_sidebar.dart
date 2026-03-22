import 'package:flutter/material.dart';
import '../../core/constants.dart';

class AppSidebar extends StatelessWidget {
  final Widget? header;
  final Widget body;
  final Widget? footer;
  final double width;

  const AppSidebar({
    super.key,
    this.header,
    required this.body,
    this.footer,
    this.width = 280,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.pureBlack,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) header!,
          Expanded(child: body),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}
