import 'package:flutter/material.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, left: 18, right: 18),
          child: Text(
            'Сообщения',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF070707),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFF3F3F4),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.chat_bubble_outline,
                      size: 40,
                      color: const Color(0xFF050505),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Пока нет сообщений',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF070707),
                  ),
                ),
                const SizedBox(height: 9),
                const SizedBox(
                  width: 280,
                  child: Text(
                    'Здесь появятся диалоги с другими пользователями.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF85858B),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
