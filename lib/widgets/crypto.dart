import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../utils/fluffy_share.dart';

class FractalCrypto extends StatefulWidget {
  final String name;
  const FractalCrypto({
    required this.name,
    Key? key,
  }) : super(key: key);

  @override
  State<FractalCrypto> createState() => _FractalCryptoState();
}

class _FractalCryptoState extends State<FractalCrypto> {
  String eth = '';
  @override
  void initState() {
    fetchEth();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return eth.isNotEmpty
        ? ListTile(
            title: Text('Ethereum address'),
            subtitle: Text(eth),
            trailing: Icon(Icons.currency_exchange),
            onTap: () => FluffyShare.share(
              eth,
              context,
            ),
          )
        : Text('No Crypto address');
  }

  fetchEth() async {
    final name = widget.name.substring(1).split(':')[0];
    final response =
        await http.get(Uri.parse('https://slyverse.com/users/' + name));

    if (response.statusCode == 200) {
      final m = jsonDecode(response.body);
      if (m['eth'] != null) {
        setState(() {
          eth = m['eth'];
        });
      }
    }
  }
}
