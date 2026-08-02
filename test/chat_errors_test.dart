import 'package:clothes/features/chat/chat_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostic message keeps actionable codes and redacts secrets', () {
    const failure = ChatFailure(
      code: ChatFailureCode.validationError,
      operation: 'send_message',
      message:
          'cannot_message_own_product Bearer very-secret-token '
          'https://internal.example/path user@example.com '
          '123e4567-e89b-12d3-a456-426614174000',
      postgrestCode: '22023',
    );

    final message = failure.diagnosticMessage;

    expect(message, contains('Это ваше объявление'));
    expect(message, contains('CHAT_VALIDATION_ERROR'));
    expect(message, contains('операция: send_message'));
    expect(message, contains('сервер: 22023'));
    expect(message, isNot(contains('very-secret-token')));
    expect(message, isNot(contains('https://')));
    expect(message, isNot(contains('user@example.com')));
    expect(message, isNot(contains('123e4567-e89b-12d3-a456-426614174000')));
  });

  test('false callback gets a stable operation code', () {
    expect(
      chatOperationFailureMessage(
        fallback: 'Сообщение не доставлено.',
        operation: 'retry_product',
      ),
      'Сообщение не доставлено.\nКод: CHAT_UI_RETRY_PRODUCT',
    );
  });

  test('product availability backend error has a Russian explanation', () {
    const failure = ChatFailure(
      code: ChatFailureCode.validationError,
      operation: 'create_product_thread',
      message: 'product_not_available',
    );

    expect(failure.userMessage, 'Объявление больше недоступно.');
  });

  test('unknown validation text is exposed only through the sanitizer', () {
    const failure = ChatFailure(
      code: ChatFailureCode.validationError,
      operation: 'send_message',
      message: 'invalid +7 (999) 123-45-67 for private@example.com',
    );

    final diagnostic = failure.diagnosticMessage;
    expect(diagnostic, contains('Проверьте данные сообщения'));
    expect(diagnostic, contains('[телефон скрыт]'));
    expect(diagnostic, contains('[email скрыт]'));
    expect(diagnostic, isNot(contains('+7 (999) 123-45-67')));
    expect(diagnostic, isNot(contains('private@example.com')));
  });
}
