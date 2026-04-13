import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final url = Uri.parse('http://localhost:1234/v1/models');
  try {
    print('GET $url with Authorization: Bearer lmstudio');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer lmstudio'},
    );
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }
}
