import 'package:cosmictransit/models/mind_energy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a full month', () {
    final m = MindEnergyMonth.fromJson({
      'month': '2026-10',
      'days': [
        {
          'date': '2026-10-05',
          'overthinking': 72,
          'vitality': 40.5,
          'focus': 61,
          'irritability': 33,
          'steadiness': 58.5,
          'drivers': [
            {
              'metric': 'overthinking',
              'label': 'Moon square Mercury',
              'delta': 8,
            },
            {'metric': 'vitality', 'label': 'Mars trine Sun', 'delta': -3.5},
          ],
        },
      ],
    });
    expect(m.month, '2026-10');
    final d = m.days.single;
    expect(d.dayOfMonth, 5);
    expect(d.overthinking, 72.0);
    expect(d.vitality, 40.5);
    expect(d.focus, 61.0);
    expect(d.irritability, 33.0);
    expect(d.steadiness, 58.5);
    expect(d.drivers, hasLength(2));
    expect(d.drivers[1].metric, 'vitality');
    expect(d.drivers[1].delta, -3.5);
  });

  test('parses the dasha period and tolerates its absence', () {
    final d = MindEnergyDay.fromJson({
      'date': '2026-09-01',
      'period': {
        'mahadasha': 'Jupiter',
        'antardasha': 'Moon',
        'pratyantardasha': 'Saturn',
        'pratyantardashaStart': '2026-07-08',
        'pratyantardashaEnd': '2026-09-23',
      },
    });
    expect(d.period!.pratyantardasha, 'Saturn');
    expect(d.period!.pratyantardashaEnd, '2026-09-23');
    expect(MindEnergyDay.fromJson({'date': '2026-09-01'}).period, isNull);
  });

  test('missing and null fields fall back to defaults', () {
    final m = MindEnergyMonth.fromJson({'days': null});
    expect(m.month, '');
    expect(m.days, isEmpty);

    final d = MindEnergyDay.fromJson({'date': null, 'overthinking': null});
    expect(d.date, '');
    expect(d.dayOfMonth, 0);
    expect(d.overthinking, 0);
    expect(d.vitality, 0);
    expect(d.focus, 0);
    expect(d.irritability, 0);
    expect(d.steadiness, 0);
    expect(d.drivers, isEmpty);

    final dr = MindEnergyDriver.fromJson({});
    expect(dr.metric, '');
    expect(dr.label, '');
    expect(dr.delta, 0);
  });
}
