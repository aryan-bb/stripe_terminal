// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:developer' as text;
import 'package:app_settings/app_settings.dart';
import 'package:example/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart' as Dio;
import 'package:mek_stripe_terminal/mek_stripe_terminal.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';

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
  TextEditingController controller = TextEditingController();

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

  // Future<bool> startNFCReading() async {
  //   try {

  //     //We first check if NFC is available on the device.
  //     if (isAvailable) {
  //       //If NFC is available, start an NFC session and listen for NFC tags to be discovered.
  //       await NfcManager.instance.startSession(
  //         onDiscovered: (NfcTag tag) async {
  //           // Process NFC tag, When an NFC tag is discovered, print its data to the console.
  //           showSnackBar('NFC Tag Detected: ${tag.data}', context);
  //         },
  //       );
  //       return isAvailable;
  //     } else {
  //       setState(() {
  //         isLoading = false;
  //       });
  //       showSnackBar('NFC not available.', context);
  //       return false;
  //     }
  //   } catch (e) {
  //     setState(() {
  //       isLoading = false;
  //     });
  //     showSnackBar('Error reading NFC: $e', context);
  //     return false;
  //   }
  // }

  //if testing >> true otherwise false
  Future<void> _startDiscoverReaders(Terminal terminal) async {
    final List<Reader> readers = [];
    const bool isSimulated = true;

    // final bool nfcAvailable = await startNFCReading();

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
          final bool isAvailable = await NfcManager.instance.isAvailable();
          if (isAvailable == false) {
            final String appName = myPackageData['appName'];
            await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  alignment: Alignment.bottomCenter,
                  title: const Icon(
                    Icons.bluetooth_audio_rounded,
                    color: Colors.blue,
                  ),
                  content: RichText(
                      text: TextSpan(children: [
                    const TextSpan(
                        text: 'Allow ',
                        style: TextStyle(
                            color: Colors.grey, fontWeight: FontWeight.normal)),
                    TextSpan(
                        text: appName,
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                    const TextSpan(
                        text:
                            ' to find , connect to , and determine the relative nfc devices for contactless payment',
                        style: TextStyle(
                            color: Colors.grey, fontWeight: FontWeight.normal))
                  ])),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        // Add your cancel function here
                      },
                      child: const Text("Don't allow",
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                    ),
                    TextButton(
                      onPressed: ()async {
                      await AppSettings.openAppSettings(type: AppSettingsType.nfc)
                            .then((value) async {
                          Navigator.of(context).pop();
                          readers.addAll(discoveredReaders);

                          // Check if any readers were discovered
                          if (readers.isNotEmpty) {
                            // After getting all the available readers, it's time to select any one reader and connect it
                            await _connectReader(terminal, readers.first);
                            setState(() {});
                          }

                          showSnackBar('Reader discovery done!', context);
                        });
                      },
                      child: const Text('Allow',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                    ),
                  ],
                );
              },
            );
          }
        }
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (e is TerminalException) {
        final String errorMessage = (e).message;
        showSnackBar('$errorMessage', context);
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

  PaymentIntent? _paymentIntent;
  CancelableFuture<PaymentIntent>? _collectingPaymentMethod;

  Future<void> _createPaymentIntent(Terminal terminal, String amount) async {
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

  void proceedTapToPay(String amount) async {
    isLoading = true;
    setState(() {});
    await _initTerminal();
    await fetchLocations(_terminal!);
    await _startDiscoverReaders(_terminal!).then((value) async {
      await _createPaymentIntent(_terminal!, amount);
      await _collectPaymentMethod(_terminal!, _paymentIntent!);
      isLoading = false;
      setState(() {});
    });
  }

  Map<String, dynamic> myPackageData = {};
  @override
  void initState() {
    super.initState();
    unawaited(PackageInfo.fromPlatform().then((value) {
      myPackageData = value.data;
      setState(() {});
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextFormField(
              enabled: isLoading == false ? true : false,
              controller: controller,
              decoration: InputDecoration(hintText: 'Enter amount Here'),
            ),
          ),
          const SizedBox(
            height: 20,
          ),
          Center(
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  isLoading = true;
                });

                var amount;

                if (controller.text.isNotEmpty) {
                  amount = double.tryParse(controller.text);
                } else {
                  amount = 1.0; // Default value if the field is empty
                }

                if (amount != null && amount > 1.0) {
                  proceedTapToPay(amount.toString());
                } else {
                  showSnackBar('Please Enter a Valid Value', context);
                  setState(() {
                    isLoading = false;
                  });
                }
              },
              child:
                  isLoading ? CircularProgressIndicator() : Text('Tap to Pay'),
            ),
          ),
        ],
      ),
    );
  }
}
