import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

final class SecureMediaUploadGrant {
  const SecureMediaUploadGrant({
    required this.bucket,
    required this.objectPath,
    required this.contentType,
    required this.sizeBytes,
    required this.token,
  });

  final String bucket;
  final String objectPath;
  final String contentType;
  final int sizeBytes;
  final String token;
}

final class SecureMediaUploadException implements Exception {
  const SecureMediaUploadException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'SecureMediaUploadException($code): $message';
}

/// Requests a narrowly scoped upload token from the server, then uploads the
/// bytes to that exact bucket/path without relying on client INSERT policies.
final class SecureMediaUploadClient {
  SecureMediaUploadClient(this._client);

  final SupabaseClient _client;

  Future<SecureMediaUploadGrant> createGrant({
    required String bucket,
    required String objectPath,
    required String contentType,
    required int sizeBytes,
  }) async {
    final response = await _invoke(
      fallbackCode: 'upload_signing_failed',
      body: {
        'action': 'prepare',
        'bucket': bucket,
        'object_path': objectPath,
        'content_type': contentType,
        'size_bytes': sizeBytes,
      },
    );
    final data = response.data;
    if (data is! Map) {
      throw const SecureMediaUploadException(
        'invalid_upload_grant',
        'The secure upload contract is invalid',
      );
    }

    final responseBucket = data['bucket']?.toString() ?? '';
    final responsePath = data['object_path']?.toString() ?? '';
    final responseContentType = data['content_type']?.toString() ?? '';
    final responseSize = data['size_bytes'];
    final token = data['token']?.toString() ?? '';
    if (responseBucket != bucket ||
        responsePath != objectPath ||
        responseContentType != contentType ||
        responseSize != sizeBytes ||
        token.isEmpty) {
      throw const SecureMediaUploadException(
        'invalid_upload_grant',
        'The secure upload contract is invalid',
      );
    }

    return SecureMediaUploadGrant(
      bucket: responseBucket,
      objectPath: responsePath,
      contentType: responseContentType,
      sizeBytes: sizeBytes,
      token: token,
    );
  }

  Future<void> claimUpload(SecureMediaUploadGrant grant) async {
    final response = await _invoke(
      fallbackCode: 'media_claim_failed',
      body: {
        'action': 'claim',
        'bucket': grant.bucket,
        'object_path': grant.objectPath,
        'content_type': grant.contentType,
        'size_bytes': grant.sizeBytes,
      },
    );
    final data = response.data;
    if (data is! Map ||
        data['claimed'] != true ||
        data['bucket']?.toString() != grant.bucket ||
        data['object_path']?.toString() != grant.objectPath) {
      throw const SecureMediaUploadException(
        'invalid_media_claim_result',
        'The uploaded object could not be finalized',
      );
    }
  }

  Future<String> uploadBinary({
    required String bucket,
    required String objectPath,
    required String contentType,
    required Uint8List bytes,
    String cacheControl = '3600',
  }) async {
    final grant = await createGrant(
      bucket: bucket,
      objectPath: objectPath,
      contentType: contentType,
      sizeBytes: bytes.length,
    );
    try {
      await _client.storage
          .from(grant.bucket)
          .uploadBinaryToSignedUrl(
            grant.objectPath,
            grant.token,
            bytes,
            FileOptions(
              cacheControl: cacheControl,
              contentType: grant.contentType,
              upsert: false,
            ),
          );
    } on StorageException catch (error) {
      final message = error.message.toLowerCase();
      final isExistingObject =
          error.statusCode == '409' ||
          message.contains('already exists') ||
          message.contains('duplicate');
      if (!isExistingObject) rethrow;
    }
    // A service-signed upload may initially have no owner_id. Claiming is a
    // required second phase, and is also retried after an idempotent 409.
    await claimUpload(grant);
    return grant.objectPath;
  }

  Future<FunctionResponse> _invoke({
    required Map<String, Object> body,
    required String fallbackCode,
  }) async {
    try {
      return await _client.functions.invoke('create-media-upload', body: body);
    } on FunctionException catch (error) {
      final details = error.details;
      throw SecureMediaUploadException(
        details is Map
            ? details['code']?.toString() ?? fallbackCode
            : fallbackCode,
        details is Map
            ? details['message']?.toString() ?? 'Secure upload failed'
            : 'Secure upload failed',
      );
    }
  }
}
