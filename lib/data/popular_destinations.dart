class PopularDestination {
  const PopularDestination({
    required this.name,
    required this.region,
    required this.image,
  });

  final String name;
  final String region;
  final String image;
}

const popularDestinations = <PopularDestination>[
  PopularDestination(
    name: 'Jaipur',
    region: 'Rajasthan',
    image: 'jaipur',
  ),
  PopularDestination(
    name: 'Varanasi',
    region: 'Uttar Pradesh',
    image: 'varanasi',
  ),
  PopularDestination(
    name: 'Udaipur',
    region: 'Rajasthan',
    image: 'udaipur',
  ),
  PopularDestination(
    name: 'Manali',
    region: 'Himachal Pradesh',
    image: 'manali',
  ),
  PopularDestination(
    name: 'Goa',
    region: 'Goa',
    image: 'goa',
  ),
  PopularDestination(
    name: 'Rishikesh',
    region: 'Uttarakhand',
    image: 'rishikesh',
  ),
];
