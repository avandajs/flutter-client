import 'dart:convert';

import 'package:avanda/avanda.dart';

/// [Avanda.config] and [Avanda.headers] are static, so state leaks between
/// tests unless every test resets them first.
void resetAvandaStatics() {
  Avanda.config = AvandaConfig(rootUrl: null);
  Avanda.headers = {};
}

/// Decodes the JSON that [Avanda.toLink] produces so tests can assert on the
/// wire format the server actually receives.
Map<String, dynamic> linkOf(Avanda query) =>
    jsonDecode(query.toLink()) as Map<String, dynamic>;

/// Pulls the `query` parameter back out of a request URL built by
/// `makeRequest`, undoing the percent-encoding applied by [Uri.parse].
Map<String, dynamic> queryParamOf(Uri url) =>
    jsonDecode(url.queryParameters['query']!) as Map<String, dynamic>;
