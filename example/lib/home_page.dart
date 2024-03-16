// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:developer' as text;
import 'package:example/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart' as Dio;
import 'package:mek_stripe_terminal/mek_stripe_terminal.dart';
import 'dart:convert';

import 'utils/keyFile.dart';

class StripMethodeScreen extends StatefulWidget {
  const StripMethodeScreen({super.key});

  @override
  State<StripMethodeScreen> createState() => _StripMethodeScreenState();
}

class _StripMethodeScreenState extends State<StripMethodeScreen> {
  Terminal? _terminal;
  final dio = Dio.Dio();
  StreamController<List<Reader>>? _controller;

  //if you've used .config.json file for storing your stripe secret key you can get it from here,
  //static const String secretKey = String.fromEnvironment('STRIPE_SECRET_KEY');

  Future<String> getConnectionToken() async {
    final String basicAuth =
        'Basic ${base64.encode(utf8.encode(KeyFile.secretKey))}';
    dio.options.contentType = Dio.Headers.formUrlEncodedContentType;

    final Dio.Response connectionTokenRes = await dio.post(
        'https://api.stripe.com/v1/terminal/connection_tokens',
        options: Dio.Options(headers: {'Authorization': basicAuth}));

    if (connectionTokenRes.data['secret'] != null) {
      return connectionTokenRes.data['secret'];
    } else {
      return '';
    }
  }

  var _locations = <Location>[];
  Location? _selectedLocation;

  Future<void> fetchLocations(Terminal terminal) async {
    _locations = const [];
    final locations = await terminal.listLocations();
    _locations = locations;
    _selectedLocation = locations.first;
    if (_selectedLocation == null) {
      showSnackBar(
          'Please create location on stripe dashboard to proceed further!',
          context);
    }
    setState(() {});
  }

  StreamSubscription? _onConnectionStatusChangeSub;
  var _connectionStatus = ConnectionStatus.notConnected;
  StreamSubscription? _onPaymentStatusChangeSub;
  PaymentStatus _paymentStatus = PaymentStatus.notReady;
  StreamSubscription? _onUnexpectedReaderDisconnectSub;

  Future<void> _initTerminal() async {
    await requestPermissions();
    final connectionToken = await getConnectionToken();
    final terminal = await Terminal.getInstance(
      shouldPrintLogs: false,
      fetchToken: () async {
        return connectionToken;
      },
    );
    _terminal = terminal;
    _onConnectionStatusChangeSub =
        terminal.onConnectionStatusChange.listen((status) {
      text.log('Connection Status Changed: ${status.name}');
      _connectionStatus = status;
    });
    _onUnexpectedReaderDisconnectSub =
        terminal.onUnexpectedReaderDisconnect.listen((reader) {
      text.log('Reader Unexpected Disconnected: ${reader.label}');
    });
    _onPaymentStatusChangeSub = terminal.onPaymentStatusChange.listen((status) {
      text.log('Payment Status Changed: ${status.name}');
      _paymentStatus = status;
    });
    if (_terminal == null) {
      showSnackBar('Please try again later!', context);
    }
    setState(() {});
  }

  //if testing >> true otherwise false
  Future<void> _startDiscoverReaders(Terminal terminal) async {
    List<Reader> readers = [];
    const bool isSimulated = true;

    try {
      if (_controller == null) {
        _controller = terminal.handleStream<List<Reader>>(
          _controller,
          () => terminal.discoverReaders(
            const LocalMobileDiscoveryConfiguration(
              isSimulated: isSimulated,
            ),
          ),
        );

        await for (List<Reader> discoveredReaders in _controller!.stream) {
          readers.addAll(discoveredReaders);

          // Check if any readers were discovered
          if (readers.isNotEmpty) {
            // After getting all the available readers, it's time to select any one reader and connect it
            await _connectReader(terminal, readers.first);
            setState(() {});
          }

          showSnackBar('Reader discovery done!', context);
        }
      }
    } catch (e) {
  setState(() {
    isLoading = false;
  });
  if (e is TerminalException) {
    final String errorMessage = (e).message;
    showSnackBar(
        '$errorMessage',
        context);
  } else {
    print('Error during reader discovery: $e');
  }
}



  }

  Reader? _reader;
  Future<void> _connectReader(Terminal terminal, Reader reader) async {
    await _tryConnectReader(terminal, reader).then((value) {
      final connectedReader = value;
      if (connectedReader == null) {
        print('return');
      }
      showSnackBar(
          'Connected to a device: ${connectedReader!.label ?? connectedReader.serialNumber}',
          context);
      _reader = connectedReader;

      setState(() {});
    });
  }

  Future<Reader?> _tryConnectReader(Terminal terminal, Reader reader) async {
    String? getLocationId() {
      final locationId = _selectedLocation?.id ?? reader.locationId;
      if (locationId == null) showSnackBar('Missing location', context);
      return locationId;
    }

    final locationId = getLocationId();
    return await terminal.connectMobileReader(
      reader,
      locationId: locationId!,
    );
  }

  var amount = '17.25';
  PaymentIntent? _paymentIntent;
  CancelableFuture<PaymentIntent>? _collectingPaymentMethod;

  Future<void> _createPaymentIntent(Terminal terminal) async {
    try {
      final paymentIntent =
          await terminal.createPaymentIntent(PaymentIntentParameters(
        amount: (double.parse(double.parse(amount).toStringAsFixed(2)) * 100)
            .ceil(),
        currency: 'USD', // your currency
        captureMethod: CaptureMethod.automatic,
        paymentMethodTypes: [PaymentMethodType.cardPresent],
      ));
      _paymentIntent = paymentIntent;

      if (_paymentIntent == null) {
        showSnackBar('Payment intent is not created!', context);
      }
      showSnackBar('Payment intent created!', context);
      setState(() {});
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  bool _isPaymentCollected = false;

  Future<void> _collectPaymentMethod(
      Terminal terminal, PaymentIntent paymentIntent) async {
    final collectingPaymentMethod = terminal.collectPaymentMethod(
      paymentIntent,
      skipTipping: true,
    );
    setState(() {
      _collectingPaymentMethod = collectingPaymentMethod;
    });

    try {
      final paymentIntentWithPaymentMethod = await collectingPaymentMethod;
      _paymentIntent = paymentIntentWithPaymentMethod;
      _collectingPaymentMethod = null;
      _isPaymentCollected = true;
      setState(() {});
      showSnackBar('Payment method collected!', context);

      await _confirmPaymentIntent(_terminal!, _paymentIntent!).then((value) {
        setState(() {});
      });
    } on TerminalException catch (exception) {
      setState(() => _collectingPaymentMethod = null);
      switch (exception.code) {
        case TerminalExceptionCode.canceled:
          showSnackBar('Collecting Payment method is cancelled!', context);
        default:
          rethrow;
      }
    }
    if (_isPaymentCollected == false) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment method is not collected!')));
    }
  }

  Future<void> _confirmPaymentIntent(
      Terminal terminal, PaymentIntent paymentIntent) async {
    final processedPaymentIntent =
        await terminal.confirmPaymentIntent(paymentIntent);
    setState(() => _paymentIntent = processedPaymentIntent);
    showSnackBar('Payment processed!', context);
    // navigate to payment success screen
  }

  bool isLoading = false;

  void proceedTapToPay() async {
    isLoading = true;
    setState(() {});
    await _initTerminal();
    await fetchLocations(_terminal!);
    await _startDiscoverReaders(_terminal!).then((value) async {
      await _createPaymentIntent(_terminal!);
      await _collectPaymentMethod(_terminal!, _paymentIntent!);
      isLoading = false;
      setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: Container(
              child: isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Strip Methode applied'),
            ),
          ),
          SizedBox(
            height: 20,
          ),
          Center(
            child: ElevatedButton(
              onPressed: () {
                proceedTapToPay();
              },
              child: const Text('Tap to Pay'),
            ),
          )
        ],
      ),
    );
  }
}
