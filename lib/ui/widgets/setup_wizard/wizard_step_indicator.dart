import 'package:flutter/material.dart';
import '../../../core/constants.dart';

/// A sleek, non-interactive progress indicator for the setup wizard.
/// Displays a series of segments that light up as the user progresses.
class WizardStepIndicator extends StatelessWidget {

  const WizardStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });
  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: List.generate(totalSteps, (index) {
          final isCompleted = index < currentStep;
          final isCurrent = index == currentStep;
          
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == totalSteps - 1 ? 0 : 6,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                height: 3,
                decoration: BoxDecoration(
                  color: (isCompleted || isCurrent)
                      ? AppColors.primary
                      : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
