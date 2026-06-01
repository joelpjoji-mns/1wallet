import type { TransactionAttachment } from '@1wallet/domain/types';
import * as DocumentPicker from 'expo-document-picker';
import * as ImagePicker from 'expo-image-picker';

export type ReceiptCaptureSource = 'camera' | 'library' | 'file';

export interface ReceiptCaptureAsset {
  source: ReceiptCaptureSource;
  uri: string;
  name: string;
  mimeType?: string;
  size?: number;
  width?: number;
  height?: number;
}

export async function pickReceiptAsset(
  source: ReceiptCaptureSource,
): Promise<ReceiptCaptureAsset | null> {
  if (source === 'file') return pickReceiptFile();
  return pickReceiptImage(source);
}

async function pickReceiptImage(source: Exclude<ReceiptCaptureSource, 'file'>) {
  const permission =
    source === 'camera'
      ? await ImagePicker.requestCameraPermissionsAsync()
      : await ImagePicker.requestMediaLibraryPermissionsAsync(false);

  if (!permission.granted) {
    throw new Error(
      source === 'camera'
        ? 'Camera permission is needed to scan receipt and bill photos for OCR.'
        : 'Photo library permission is needed to choose existing receipt and bill images.',
    );
  }

  const picker =
    source === 'camera' ? ImagePicker.launchCameraAsync : ImagePicker.launchImageLibraryAsync;
  const result = await picker({
    mediaTypes: ImagePicker.MediaTypeOptions.Images,
    allowsEditing: false,
    quality: 0.82,
    exif: true,
  });

  if (result.canceled) return null;
  const asset = result.assets[0];
  if (!asset) return null;

  return {
    source,
    uri: asset.uri,
    name: asset.fileName ?? receiptNameFromUri(asset.uri, source === 'camera' ? 'jpg' : 'image'),
    mimeType: asset.mimeType,
    size: asset.fileSize,
    width: asset.width,
    height: asset.height,
  };
}

async function pickReceiptFile() {
  const result = await DocumentPicker.getDocumentAsync({
    type: ['image/*', 'application/pdf'],
    multiple: false,
    copyToCacheDirectory: true,
  });

  if (result.canceled) return null;
  const asset = result.assets[0];
  if (!asset) return null;

  return {
    source: 'file' as const,
    uri: asset.uri,
    name: asset.name || receiptNameFromUri(asset.uri, 'receipt'),
    mimeType: asset.mimeType,
    size: asset.size,
  };
}

function receiptNameFromUri(uri: string, fallbackExtension: string): string {
  const fileName = uri.split('/').pop();
  if (fileName) return fileName;
  return `receipt-${Date.now()}.${fallbackExtension}`;
}

export function receiptAssetToAttachment(
  asset: ReceiptCaptureAsset,
  createdAt: string = new Date().toISOString(),
): TransactionAttachment {
  return {
    id: `receipt-${Date.now()}-${asset.name.replace(/[^a-z0-9]/gi, '-').slice(0, 40)}`,
    name: asset.name,
    uri: asset.uri,
    mimeType: asset.mimeType,
    size: asset.size,
    width: asset.width,
    height: asset.height,
    source: asset.source,
    createdAt,
  };
}
