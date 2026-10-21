import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'constants.dart';

class SocketService {
  static final SocketService _i = SocketService._();
  factory SocketService() => _i;
  SocketService._();

  socket_io.Socket? _socket;
  bool _connected = false;

  bool get isConnected => _connected;

  void connect(String token) {
    _socket?.disconnect();
    _socket = socket_io.io(kSocketUrl, socket_io.OptionBuilder()
        .setTransports(['websocket'])
        .setAuth({'token': token})
        .enableAutoConnect()
        .build());
    _socket!.onConnect((_) => _connected = true);
    _socket!.onDisconnect((_) => _connected = false);
  }

  void on(String e, Function(dynamic) h) => _socket?.on(e, h);

  void off(String e, [Function(dynamic)? h]) {
    if (h == null) {
      _socket?.off(e);
    } else {
      _socket?.off(e, h);
    }
  }

  void emit(String e, dynamic d) {
    if (_connected) _socket?.emit(e, d);
  }

  void joinServiceRoom(int id) => emit('join_service', {'service_id': id});
  void leaveServiceRoom(int id) => emit('leave_service', {'service_id': id});
  void joinUserRoom(int id) => emit('join_user', {'user_id': id});

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _connected = false;
  }
}
