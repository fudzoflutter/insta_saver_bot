import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

void main() {
  final String botToken = "7172112889:AAFbmARFoVC_kS8AEQ_7sOB2DSfXzoVsAkw";
  final TelegramBotApi telegramBot = TelegramBotApi(tokenBot: botToken);
  int offset = 0;

  _initializeBot(telegramBot, offset);
}

void _initializeBot(TelegramBotApi telegramBot, int offset) {
  _getUpdates(telegramBot, offset);
}

Future<void> _getUpdates(TelegramBotApi telegramBot, int offset) async {
  final client = http.Client();
  while (true) {
    final response = await client.get(
      Uri.parse(
          "https://api.telegram.org/bot${telegramBot.tokenBot}/getUpdates?offset=$offset"),
      headers: {'Connection': 'Keep-Alive'},
    );

    if (response.statusCode == 200) {
      final updates = json.decode(response.body)['result'];

      for (var update in updates) {
        final message = update['message'];
        if (message != null) {
          final chatId = message['chat']['id'];
          final text = message['text'];

          if (text != null) {
            if (text == "/start") {
              // /start komandasi uchun xabar va tugma yuborish
              await telegramBot.sendMessage(
                chatId: chatId,
                text:
                    "🤖 Salom, Men instagramdan video va rasmlarni yuklab olishim mumkin.\n\n"
                    "Yuklab olish uchun menga havolani yuboring 🔻\n\n"
                    "Men media fayllarni guruhda ham yuklab olishim mumkin, "
                    "buning uchun quyidagi tugmani bosish orqali meni guruhga qo'shing",
                replyMarkup: {
                  'inline_keyboard': [
                    [
                      {
                        'text': '➕ Guruhga qo\'shish',
                        'url': 'https://t.me/fudzodown_bot?startgroup=true',
                      },
                    ],
                  ],
                },
              );
            } else if (text.contains("instagram.com") ||
                text.contains("tiktok.com")) {
              final waitingMessage = await telegramBot.sendMessage(
                  chatId: chatId,
                  text: "📥 Yuklab olinmoqda, Iltimos kuting...");

              List<String>? mediaUrls;
              if (text.contains("instagram.com")) {
                mediaUrls = await _fetchInstagramMedia(text);
              }
              if (mediaUrls != null && mediaUrls.isNotEmpty) {
                await _sendMedia(telegramBot, chatId, mediaUrls,
                    waitingMessage['result']['message_id']);
              } else {
                await telegramBot.deleteMessage(
                    chatId: chatId,
                    messageId: waitingMessage['result']['message_id']);
                telegramBot.sendMessage(
                    chatId: chatId, text: "😔 Afsuski, media topilmadi!");
              }
            } else {
              telegramBot.sendMessage(
                  chatId: chatId,
                  text: "⚠️ Iltimos, to‘g‘ri Instagram URL kiriting!");
            }
          }
        }
        offset = update['update_id'] + 1;
      }
    }
    await Future.delayed(Duration(seconds: 1));
  }
}

Future<List<String>?> _fetchInstagramMedia(String url) async {
  final response = await http.post(
    Uri.parse("http://127.0.0.1:5000/download"),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'url': url}),
  );

  if (response.statusCode != 200) {
    throw Exception('🌐 API xatosi: ${response.statusCode}');
  }

  final jsonResponse = json.decode(response.body);
  if (jsonResponse['media_urls'] == null ||
      jsonResponse['media_urls'].isEmpty) {
    return null;
  }

  return List<String>.from(jsonResponse['media_urls']);
}

Future<void> _sendMedia(TelegramBotApi telegramBot, int chatId,
    List<String> mediaUrls, int waitingMessageId) async {
  for (var mediaUrl in mediaUrls) {
    try {
      final mediaBytes = await _downloadMedia(mediaUrl);
      if (mediaUrl.contains(".mp4")) {
        await _sendVideo(telegramBot, chatId, mediaBytes);
      } else {
        await _sendImage(telegramBot, chatId, mediaBytes);
      }
    } catch (e) {
      telegramBot.sendMessage(
          chatId: chatId, text: "❌ Media yuborishda xatolik: $e");
    }
  }
  await telegramBot.deleteMessage(chatId: chatId, messageId: waitingMessageId);
}

Future<Uint8List> _downloadMedia(String mediaUrl) async {
  final response = await http.get(Uri.parse(mediaUrl));
  if (response.statusCode != 200) {
    throw Exception('😔 Afsuski, mediani yuklab olishda xatolik!');
  }
  return response.bodyBytes;
}

Future<void> _sendVideo(
    TelegramBotApi telegramBot, int chatId, Uint8List mediaBytes) async {
  final dir = Directory.systemTemp;
  final filePath = '${dir.path}/video.mp4';
  final file = File(filePath);
  await file.writeAsBytes(mediaBytes);

  var uri = Uri.parse(
      "https://api.telegram.org/bot${telegramBot.tokenBot}/sendVideo");
  var request = http.MultipartRequest('POST', uri)
    ..fields['chat_id'] = chatId.toString()
    ..fields['caption'] = "🚀@fudzodown_bot orqali yuklab olindi📥"
    ..files.add(http.MultipartFile.fromBytes(
      'video',
      File(filePath).readAsBytesSync(),
      filename: "video.mp4",
    ));
  await request.send();
}

Future<void> _sendImage(
    TelegramBotApi telegramBot, int chatId, Uint8List mediaBytes) async {
  final dir = Directory.systemTemp;
  final filePath = '${dir.path}/image.jpg';
  final file = File(filePath);
  await file.writeAsBytes(mediaBytes);

  var uri = Uri.parse(
      "https://api.telegram.org/bot${telegramBot.tokenBot}/sendPhoto");
  var request = http.MultipartRequest('POST', uri)
    ..fields['chat_id'] = chatId.toString()
    ..fields['caption'] = "🚀@fudzodown_bot orqali yuklab olindi📥"
    ..files.add(http.MultipartFile.fromBytes(
      'photo',
      File(filePath).readAsBytesSync(),
      filename: "image.jpg",
    ));
  await request.send();
}

class TelegramBotApi {
  final String tokenBot;
  TelegramBotApi({required this.tokenBot});

  Future<Map<String, dynamic>> sendMessage({
    required int chatId,
    required String text,
    Map<String, dynamic>? replyMarkup,
  }) async {
    final body = {
      'chat_id': chatId,
      'text': text,
      if (replyMarkup != null) 'reply_markup': replyMarkup,
    };
    final response = await http.post(
      Uri.parse("https://api.telegram.org/bot$tokenBot/sendMessage"),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(body),
    );
    return json.decode(response.body);
  }

  Future<void> deleteMessage(
      {required int chatId, required int messageId}) async {
    await http.post(
      Uri.parse("https://api.telegram.org/bot$tokenBot/deleteMessage"),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({'chat_id': chatId, 'message_id': messageId}),
    );
  }

  Future<void> sendVideo({required int chatId, required String video}) async {
    var uri = Uri.parse("https://api.telegram.org/bot$tokenBot/sendVideo");
    var request = http.MultipartRequest('POST', uri)
      ..fields['chat_id'] = chatId.toString()
      ..files.add(http.MultipartFile.fromBytes(
        'video',
        File(video).readAsBytesSync(),
        filename: "video.mp4",
      ));
    await request.send();
  }

  Future<void> sendPhoto({required int chatId, required String photo}) async {
    var uri = Uri.parse("https://api.telegram.org/bot$tokenBot/sendPhoto");
    var request = http.MultipartRequest('POST', uri)
      ..fields['chat_id'] = chatId.toString()
      ..files.add(http.MultipartFile.fromBytes(
        'photo',
        File(photo).readAsBytesSync(),
        filename: "image.jpg",
      ));
    await request.send();
  }
}
