import '../models/trip_draft.dart';

class MockData {
  MockData._();

  static const destinations = <DestinationOption>[
    DestinationOption(
      name: 'Ujjain',
      region: 'Madhya Pradesh',
      tags: ['Temples', 'Heritage', 'Culture'],
    ),
    DestinationOption(
      name: 'Jaipur',
      region: 'Rajasthan',
      tags: ['Forts', 'Crafts', 'Food'],
    ),
    DestinationOption(
      name: 'Varanasi',
      region: 'Uttar Pradesh',
      tags: ['Ghats', 'Culture', 'Heritage'],
    ),
    DestinationOption(
      name: 'Goa',
      region: 'Konkan Coast',
      tags: ['Beaches', 'Food', 'Relaxation'],
    ),
    DestinationOption(
      name: 'Manali',
      region: 'Himachal Pradesh',
      tags: ['Mountains', 'Nature', 'Adventure'],
    ),
    DestinationOption(
      name: 'Udaipur',
      region: 'Rajasthan',
      tags: ['Lakes', 'Palaces', 'Culture'],
    ),
    DestinationOption(
      name: 'Bengaluru',
      region: 'Karnataka',
      tags: ['Food', 'Parks', 'City life'],
    ),
    DestinationOption(
      name: 'Mumbai',
      region: 'Maharashtra',
      tags: ['Coast', 'Culture', 'Food'],
    ),
  ];

  static const arrivalPoints = <String>[
    'Ujjain Railway Station',
    'Ujjain Junction',
    'Nanakhheda Bus Stand',
  ];
}
