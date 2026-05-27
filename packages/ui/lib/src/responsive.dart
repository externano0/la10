import 'package:flutter/widgets.dart';

enum FormFactor { phone, tablet, desktop }

FormFactor formFactorOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) return FormFactor.phone;
  if (w < 1000) return FormFactor.tablet;
  return FormFactor.desktop;
}

/// Pick a widget per form factor. `tablet` falls back to `desktop` then `phone`.
Widget responsive(
  BuildContext context, {
  required Widget phone,
  Widget? tablet,
  Widget? desktop,
}) {
  switch (formFactorOf(context)) {
    case FormFactor.phone:
      return phone;
    case FormFactor.tablet:
      return tablet ?? desktop ?? phone;
    case FormFactor.desktop:
      return desktop ?? tablet ?? phone;
  }
}
