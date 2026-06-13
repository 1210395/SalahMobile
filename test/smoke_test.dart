import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amarati/app.dart';
import 'package:amarati/app_ctx.dart';
import 'package:amarati/data/sample_data.dart';

Widget _wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
      home: child,
    );

void main() {
  final screens = [
    ('splash', AppRole.guest),
    ('guestHome', AppRole.guest),
    ('login', AppRole.guest),
    ('home', AppRole.admin),
    ('building', AppRole.admin),
    ('units', AppRole.admin),
    ('payments', AppRole.admin),
    ('expenses', AppRole.admin),
    ('workers', AppRole.admin),
    ('parking', AppRole.admin),
    ('guard', AppRole.admin),
    ('elevator', AppRole.admin),
    ('craftsmen', AppRole.admin),
    ('reports', AppRole.admin),
    ('alerts', AppRole.admin),
    ('years', AppRole.admin),
    ('more', AppRole.admin),
    ('subscribe', AppRole.admin),
    ('buildingSetup', AppRole.admin),
    ('joinUnit', AppRole.resident),
    ('approvals', AppRole.admin),
    ('brandEdit', AppRole.admin),
    ('resHome', AppRole.resident),
    ('resReport', AppRole.resident),
    ('resElevator', AppRole.resident),
  ];

  for (final s in screens) {
    testWidgets('renders ${s.$1}', (tester) async {
      await tester.pumpWidget(_wrap(
          AmaratiApp(initialScreen: s.$1, initialRole: s.$2, initialBtype: BType.residential)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: 'exception while building ${s.$1}');
    });
  }
}
