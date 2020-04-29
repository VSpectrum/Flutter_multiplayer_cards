import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:device_id/device_id.dart';
import 'package:uuid/uuid.dart';
import 'package:share/share.dart';
import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:typed_data/typed_data.dart' as typed;
import 'dart:convert';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cards',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: GameArea(title: 'Cards'),
    );
  }
}

class GameArea extends StatefulWidget {
  GameArea({Key key, this.title}) : super(key: key);
  final String title;

  @override
  GameState createState() => GameState();
}

class ActionLog {
  //todo: develop further nearing end (to map to draw/play/points events)
  Map action = {'player_name': 'Action'};
  List log = [];
}

class PlayerHand {
  List cards = [];

  PlayerHand([this.cards]) {
    if (this.cards == null) {
      this.cards = [];
    }
  }

  factory PlayerHand.fromJson(dynamic json) {
    var jCards = jsonDecode(json)['cards'];
    List _cards =
    jCards.map((cardObjsJson) => Card.fromJson(cardObjsJson)).toList();

    return PlayerHand(_cards);
  }

  @override
  String toString() {
    return '{ "cards":${this.cards} }';
  }

  void loadCard(String card) {
    //todo: load card into hand sorted (auto scroll to new card)
    this.cards.add(Card(card));
  }

  void playCard(
      Card card, PlayedCards playedCards, String player, Function setState) {
    setState(() {
      if (this.cards.length > 0) {
        int cardIndex = this.cards.indexOf(card);
        Card cardDrawn = this.cards.removeAt(cardIndex);
        cardDrawn.playedBy = player;
        playedCards.playedList.add(cardDrawn);
      } else {
        developer.log('hand is empty');
      }
    });
  }
}

class Deck {
  //todo: auto fetch cards list based on assets subfolder content
  List cards = [
    "10C","10D","10H","10S","2C", "2D", "2H", "2S", "3C", "3D", "3H", "3S", "4C", "4D", "4H", "4S", "5C", "5D", "5H", "5S", "6C", "6D", "6H", "6S", "7C", "7D", "7H", "7S", "8C", "8D", "8H", "8S", "9C", "9D", "9H", "9S", "AC", "AD", "AH", "AS", "JC", "JD", "JH", "JS", "KC", "KD", "KH", "KS", "QC", "QD", "QH", "QS"
  ];

  @override
  String toString() {
    return json.encode(cards);
  }

  factory Deck.fromJson(dynamic json) {
    var jDeck = jsonDecode(json);
    var _cards = jDeck as List;

    return Deck(_cards);
  }

  Deck([List updatedCards]) {
    if (updatedCards != null) {
      this.cards = updatedCards;
    } else {
      this.cards = this.shuffle();
    }
  }

  List shuffle() {
    var random = new Random();
    for (var i = this.cards.length - 1; i > 0; i--) {
      var n = random.nextInt(i + 1);
      var temp = this.cards[i];
      this.cards[i] = this.cards[n];
      this.cards[n] = temp;
    }
    return this.cards;
  }

  void drawCard(List handList, Function setState) {
    //this.shuffle();
    setState(() {
      if (this.cards.length > 0) {
        String cardDrawn = this.cards.removeLast();
        handList.add(Card(cardDrawn));
        developer.log(cardDrawn);
      } else {
        developer.log('No more cards in deck to draw from');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return null;
  }
}

//todo: add mqtt publishes to methods
class PlayedCards {
  List playedList = []; // list of Card objects

  PlayedCards([this.playedList]) {
    if (this.playedList == null) {
      this.playedList = [];
    }
  }

  factory PlayedCards.fromJson(dynamic json) {
    var jCards = jsonDecode(json)['playedCards'];
    List _cards =
    jCards.map((cardObjsJson) => Card.fromJson(cardObjsJson)).toList();

    return PlayedCards(_cards);
  }

  @override
  String toString() {
    return '{ "playedCards":${this.playedList} }';
  }

  void addCard(Card card) {
    this.playedList.add(card);
  }

  void removeCard(Card card) {
    this.playedList.removeAt(this.playedList.indexOf(card));
  }
}

class Card {
  double x = 0;
  double y = 0;
  String card;
  String cardDisp;
  bool isFaceUp = true;
  String playedBy;

  @override
  String toString() {
    return '{ "card":"${this.card}", "x":${this.x}, "y":${this.y}, "isFaceUp":${this.isFaceUp}, "playedBy":"${this.playedBy}" }';
  }

  factory Card.fromJson(dynamic json) {
    return Card(
      json['card'] as String,
      json['x'] as double,
      json['y'] as double,
      json['isFaceUp'] as bool,
      json['playedBy'] as String,
    );
  }

  Card(this.card,
      [this.x = 40, this.y = 40, this.isFaceUp = true, this.playedBy = '']) {
    if (isFaceUp) {
      this.cardDisp = this.card + '.svg';
    } else {
      this.cardDisp = 'back.svg';
    }
  }

  void flip(Function setState) {
    setState(() {
      if (isFaceUp) {
        this.isFaceUp = false;
        this.cardDisp = 'back.svg';
      } else {
        this.isFaceUp = true;
        this.cardDisp = this.card + '.svg';
      }
    });
  }
}

class GameState extends State<GameArea> {
  Future<void> initDeviceId() async {
    String deviceID = await DeviceId.getID;
    setState(() {
      thisDevice = deviceID;
    });
  }

  @override
  void initState() {
    super.initState();
    initDeviceId();
    _connect();
  }

  Deck cardDeck = Deck();
  PlayerHand playerHand = PlayerHand();
  PlayedCards playedCards = PlayedCards(); // list of Card objects
  ActionLog actionLog = ActionLog();
  String statusMsg = 'Test Phase';
  Offset offset = Offset.zero;
  String thisDevice = '';
  String roomID = Uuid().v4().replaceAll('-', '_');
  Map playerList = {
    //DeviceId.getID: 'Player 1'  // map deviceID to a playername for better repr
  }; //todo: on mqtt recv update playermap + playerhand
  final joinRoomID = TextEditingController();
  final playerName = TextEditingController();

  String broker = '------------------------';
  int port = 8887;
  String username = '-----';
  String passwd = '---------';
  String clientIdentifier = Uuid().v4();
  mqtt.MqttClient client;
  mqtt.MqttConnectionState
  connectionState; //todo: consider making this observable
  StreamSubscription subscription;

  void _subscribeToTopic(String topic) {
    if (connectionState == mqtt.MqttConnectionState.connected) {
      print('[MQTT client] Subscribing to ${topic.trim()}');
      client.subscribe(topic, mqtt.MqttQos.exactlyOnce);
    }
  }

  void _connect() async {
    client = mqtt.MqttClient.withPort(broker, '', port);
    client.logging(on: true);
    client.keepAlivePeriod = 15;
    client.onDisconnected = this._onDisconnected;

    final mqtt.MqttConnectMessage connMess = mqtt.MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .startClean() // Non persistent session for testing
        .keepAliveFor(15)
        .withWillQos(mqtt.MqttQos.atMostOnce);
    print('[MQTT client] MQTT client connecting....');
    client.connectionMessage = connMess;

    try {
      await client.connect(username, passwd);
    } catch (e) {
      print(e);
      _disconnect();
    }

    if (client.connectionState == mqtt.MqttConnectionState.connected) {
      print('[MQTT client] connected');
      this.setState(() {
        connectionState = client.connectionState;
      });
    } else {
      print('[MQTT client] ERROR: MQTT client connection failed - '
          'disconnecting, state is ${client.connectionState}');
      _disconnect();
    }

    /// The client has a change notifier object(see the Observable class) which we then listen to to get
    /// notifications of published updates to each subscribed topic.
    subscription = client.updates.listen(_onMessage);

    _subscribeToTopic('cards/${this.roomID}/#');
  }

  void _disconnect() {
    print('[MQTT client] _disconnect()');
    this.client.disconnect();
    _onDisconnected();
  }

  void _onDisconnected() async {
    print('[MQTT client] _onDisconnected');
    this.setState(() {
      //topics.clear();
      connectionState = this.client.connectionState;
      this.client = mqtt.MqttClient.withPort(this.broker, '', this.port);
      subscription.cancel();
      this.subscription = null;
    });
    print('[MQTT client] MQTT client disconnected. Attempting reconnect');
    while (connectionState != mqtt.MqttConnectionState.connected) {
      try {
        await this.client.connect(username, passwd);
      } catch (e) {
        print(e);
        _disconnect();
      }
    }
  }

  //todo: on messages will need to have setState for updates to UI
  void _onMessage(List<mqtt.MqttReceivedMessage> event) {
//    print(event.length);
    final mqtt.MqttPublishMessage recMess =
    event[0].payload as mqtt.MqttPublishMessage;
    final String message =
    mqtt.MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    String topic = event[0].topic;

    setState(() {
      if (topic == "cards/$roomID/$thisDevice") {
        playerHand = PlayerHand.fromJson(message);
      }
      else if (topic == "cards/$roomID/played") {
        playedCards = PlayedCards.fromJson(message);
      }
      else if (topic == "cards/$roomID/deck") {
        cardDeck = Deck.fromJson(message);
      }

      else if (topic == "cards/$roomID/field/pickup") {
        List instr = message.split(" ");
        statusMsg = '${instr[0]} picked up card from ${instr[1]}';
      }

      else if (topic == "cards/$roomID/field/played") {
        List instr = message.split(" ");
        statusMsg = '${instr[0]} played card';
      }

      else if (topic == "cards/$roomID/field/flip") {
        List instr = message.split(" ");
        statusMsg = '${instr[0]} flipped card on field';
      }

      else if (topic == "cards/$roomID/field/move") {
        List instr = message.split(" ");
        if (instr[0] != thisDevice) {
          int idx = playedCards.playedList
              .indexWhere((card) => card.card == instr[1]);
          playedCards.playedList[idx].x = double.parse(instr[2]);
          playedCards.playedList[idx].y = double.parse(instr[3]);
          statusMsg = '${instr[0]} moving card';
        }
      }

      else if (topic == "cards/$roomID/reset") {
        if (message == "true") {
          playerHand.cards = [];
          statusMsg = 'Game Reset';
        }
      }
    });
  }

  @override
  void dispose() {
    joinRoomID.dispose();
    super.dispose();
  }

  void resetState() {
    var encoded = utf8.encode("true");
    typed.Uint8Buffer data = typed.Uint8Buffer();
    data.addAll(encoded);
    client.publishMessage(
        'cards/$roomID/reset', mqtt.MqttQos.exactlyOnce, data,
        retain: true);
  }

  void syncState() {
    //playerList
    //todo: playerList not important rn

    //playerHands
    //todo: for sub, if two players have same card in hand. remove one card (race condition) - force only one existence of card
    String sPlayerHand = playerHand.toString();
    var encoded = utf8.encode(sPlayerHand);
    typed.Uint8Buffer data = typed.Uint8Buffer();
    data.addAll(encoded);
    client.publishMessage(
        'cards/$roomID/$thisDevice', mqtt.MqttQos.exactlyOnce, data,
        retain: true);

    //playedCards
    String sPlayedCards = playedCards.toString();
    encoded = utf8.encode(sPlayedCards);
    data = typed.Uint8Buffer();
    data.addAll(encoded);
    client.publishMessage(
        'cards/$roomID/played', mqtt.MqttQos.exactlyOnce, data,
        retain: true);

    //cardDeck
    String sDeck = cardDeck.toString();
    encoded = utf8.encode(sDeck);
    data = typed.Uint8Buffer();
    data.addAll(encoded);
    client.publishMessage('cards/$roomID/deck', mqtt.MqttQos.exactlyOnce, data,
        retain: true);
  }

  List<Widget> _generateField(double height) {
    List fieldObjects = playedCards.playedList
        .map((card) => Positioned(
        left: card.x * MediaQuery.of(context).size.width / 80,
        top: card.y * height / 80,
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              offset = Offset(
                  details.delta.dx + card.x, details.delta.dy + card.y);
              card.x = offset.dx;
              card.y = offset.dy;

              String msg = '$thisDevice ${card.card} ${card.x} ${card.y}';
              var encoded = utf8.encode(msg);
              typed.Uint8Buffer data = typed.Uint8Buffer();
              data.addAll(encoded);
              client.publishMessage('cards/$roomID/field/move',
                  mqtt.MqttQos.atLeastOnce, data,
                  retain: false);
            });
          },
          onDoubleTap: () {
            setState(() {
              playedCards.removeCard(card);
              playerHand.cards.add(card);
              syncState(); //state is only used for game load (retain: True)

              String msg = '$thisDevice field';
              var encoded = utf8.encode(msg);
              typed.Uint8Buffer data = typed.Uint8Buffer();
              data.addAll(encoded);
              client.publishMessage('cards/$roomID/field/pickup',
                  mqtt.MqttQos.atLeastOnce, data,
                  retain: true);
            });
          },
          onTap: () {
            developer.log('card tapped');
            card.flip(setState);
            syncState();

            String msg = '$thisDevice ${card.card}';
            var encoded = utf8.encode(msg);
            typed.Uint8Buffer data = typed.Uint8Buffer();
            data.addAll(encoded);
            client.publishMessage('cards/$roomID/field/flip',
                mqtt.MqttQos.atLeastOnce, data,
                retain: true);
          },
          child: SvgPicture.asset(
            'assets/cards/${card.cardDisp}',
            height: 140,
          ),
        )))
        .toList();

    fieldObjects.add(Positioned(
      left: MediaQuery.of(context).size.width - 100,
      top: height-140,
      child: GestureDetector(
        child: SvgPicture.asset('assets/cards/back.svg', height: 140),
        onDoubleTap: () {
          developer.log("Draw Card");
          cardDeck.drawCard(playerHand.cards, setState);
          String msg = '$thisDevice deck';
          var encoded = utf8.encode(msg);
          typed.Uint8Buffer data = typed.Uint8Buffer();
          data.addAll(encoded);
          client.publishMessage('cards/$roomID/field/pickup',
              mqtt.MqttQos.atLeastOnce, data,
              retain: true);
        },
      ),
    ));

    return fieldObjects;
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called
    return Scaffold(
      appBar: AppBar(
          actions: <Widget>[
            RaisedButton(
              child: Text("Reset\nGame"),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return Dialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 10,
                      child: Container(
                        height: 250.0,
                        width: 360.0,
                        child: ListView(
                          children: <Widget>[
                            SizedBox(height: 20),
                            Center(
                              child: Text(
                                "Reset Game",
                                style: TextStyle(
                                    fontSize: 24,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(height: 10),
                            Divider(color: Colors.black),
                            SizedBox(height: 20),
                            Center(
                              child: Text(
                                "Are you sure you wish to reset?",
                                style: TextStyle(
                                    fontSize: 14, color: Colors.black),
                              ),
                            ),
                            SizedBox(height: 20),
                            Center(
                                child: RaisedButton(
                                    color: Colors.green,
                                    child: Text(
                                      "Reset",
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(context, true);
                                      setState(() {
                                        cardDeck = Deck();
                                        playerHand = PlayerHand();
                                        playedCards.playedList = [];
                                      });
                                      syncState();
                                      resetState();
                                    })),
                            Center(
                                child: RaisedButton(
                                    color: Colors.red,
                                    child: Text(
                                      "Cancel",
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(context, false);
                                    })),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            Spacer(),
            RaisedButton(
              child: Text("Player\nName"),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return Dialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 16,
                      child: Container(
                        height: 270.0,
                        width: 360.0,
                        child: ListView(
                          children: <Widget>[
                            SizedBox(height: 20),
                            Center(
                              child: Text(
                                "Player Name",
                                style: TextStyle(
                                    fontSize: 24,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(height: 10),
                            Divider(color: Colors.black),
                            SizedBox(height: 20),
                            Center(
                              child: Text(
                                "Enter a name for yourself below.\n\n(Less than 20 letters long)",
                                style: TextStyle(
                                    fontSize: 14, color: Colors.black),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            SizedBox(height: 10),
                            Container(
                              margin: const EdgeInsets.only(
                                  left: 28.0, right: 28.0),
                              child: Column(
                                children: <Widget>[
                                  TextField(
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 13),
                                    controller: playerName,
                                  ),
                                  SizedBox(height: 10),
                                  RaisedButton(
                                      color: Colors.green,
                                      child: Text(
                                        "Save",
                                        style: TextStyle(color: Colors.white),
                                        textAlign: TextAlign.center,
                                      ),
                                      onPressed: () {
                                        Navigator.pop(context, true);
                                        setState(() {
                                          if (playerName.text.length <= 20) {
                                            playerList[thisDevice] =
                                                playerName.text.trim();
                                          }
                                        });
                                        //String topic  = "cards/$roomID/$thisDevice";

                                        //client.publishMessage(topic, mqtt.MqttQos.exactlyOnce, data, retain: true);
                                      })
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            Spacer(),
            RaisedButton(
              child: Text("Room"),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return Dialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 16,
                      child: Container(
                        height: 450.0,
                        width: 360.0,
                        child: ListView(
                          children: <Widget>[
                            SizedBox(height: 20),
                            Center(
                              child: Text(
                                "Room Options",
                                style: TextStyle(
                                    fontSize: 24,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(height: 10),
                            Divider(color: Colors.black),
                            SizedBox(height: 20),
                            Center(
                              child: Text(
                                "Share Room",
                                style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(height: 10),
                            Container(
                                margin: const EdgeInsets.only(
                                    left: 28.0, right: 28.0),
                                child: Column(
                                  children: <Widget>[
                                    Text("Below is your room ID"),
                                    TextFormField(
                                      decoration: new InputDecoration(
                                        border: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        errorBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                      ),
                                      initialValue: roomID,
                                      readOnly: true,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    Container(
                                        child: Row(
                                          children: <Widget>[
                                            Expanded(
                                                flex: 5,
                                                child: RaisedButton(
                                                    child: Text(
                                                      "Copy to Clipboard",
                                                      style: TextStyle(
                                                          color: Colors.black),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                    onPressed: () {
                                                      Clipboard.setData(
                                                          new ClipboardData(
                                                              text: roomID));
                                                      Navigator.pop(context, true);
                                                    })),
                                            Spacer(flex: 1),
                                            Expanded(
                                                flex: 5,
                                                child: RaisedButton(
                                                    child: Text(
                                                      "Share",
                                                      style: TextStyle(
                                                          color: Colors.black),
                                                    ),
                                                    onPressed: () {
                                                      Share.share(
                                                          'Below is my room ID on the Cards app:\n$roomID');
                                                      Navigator.pop(context, true);
                                                    })),
                                          ],
                                        )),
                                    SizedBox(height: 10),
                                    Divider(color: Colors.black),
                                  ],
                                )),
                            SizedBox(height: 20),
                            Center(
                              child: Text(
                                "Join Room",
                                style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(height: 10),
                            Container(
                                margin: const EdgeInsets.only(
                                    left: 28.0, right: 28.0),
                                child: Column(
                                  children: <Widget>[
                                    Text("Paste room ID below"),
                                    TextField(
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 13),
                                      controller: joinRoomID,
                                    ),
                                    SizedBox(height: 10),
                                    RaisedButton(
                                        color: Colors.green,
                                        child: Text(
                                          "Join Room",
                                          style: TextStyle(color: Colors.white),
                                          textAlign: TextAlign.center,
                                        ),
                                        onPressed: () {
                                          Navigator.pop(context, true);
                                          setState(() {
//                                            if (joinRoomID.text.length >= 36) {
                                            cardDeck = Deck();
                                            playerHand = PlayerHand();
                                            playedCards.playedList = [];

                                            client
                                                .unsubscribe('cards/$roomID/#');
                                            roomID = joinRoomID.text.trim();
                                            _subscribeToTopic(
                                                'cards/$roomID/#');
//                                            }
                                          });
                                        })
                                  ],
                                )),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ]),
      body: Container(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Container(
                height: MediaQuery.of(context).size.height * 0.64,
                child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xffeeeeee),
                      border: Border.all(
                        color: Colors.black,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Stack(children: _generateField(MediaQuery.of(context).size.height * 0.64)))),
            Container(
                height: MediaQuery.of(context).size.height * 0.05,
                child: Row(children: <Widget>[
                  Text("Status: $statusMsg"),
                  Spacer(),
//                  Text("End Turn ")
                ])),
            Container(
              height: MediaQuery.of(context).size.height * 0.2,
              color: Colors.white,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: playerHand.cards
                    .map((card) => Container(
                  child: GestureDetector(
                      child: Container(
                          color: Colors.white,
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/cards/${card.cardDisp}',
                              height: 150,
                            ),
                            widthFactor: 1.1,
                          )),
                      onDoubleTap: () {
                        developer.log("Play Card");
                        playerHand.playCard(
                            card, playedCards, thisDevice, setState);
                        syncState();

                        String msg = '$thisDevice ${card.card}';
                        var encoded = utf8.encode(msg);
                        typed.Uint8Buffer data = typed.Uint8Buffer();
                        data.addAll(encoded);
                        client.publishMessage('cards/$roomID/field/played',
                            mqtt.MqttQos.atLeastOnce, data,
                            retain: true);

                      },
                      onTap: () {
                        developer.log("Flip Card");
                        card.flip(setState);
                      }),
                ))
                    .toList(),
              ),
            )
          ],
        ),
      ),
    );
  }
}
