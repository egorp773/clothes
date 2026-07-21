import { EdgeError } from "./edge.ts";

export const accessoryImageBucket = "accessory-images";

export function canonicalAccessoryStoragePath(
  storedValue: string,
  supabaseUrl: string,
  ownerId: string,
  accessoryId: string,
): string {
  const requiredPrefix = `${ownerId}/${accessoryId}/`;
  if (storedValue.startsWith(requiredPrefix)) return validatePath(storedValue);

  if (storedValue.startsWith(`storage://${accessoryImageBucket}/`)) {
    const path = storedValue.slice(`storage://${accessoryImageBucket}/`.length);
    return assertOwnedAccessoryPath(path, requiredPrefix);
  }

  let url: URL;
  try {
    url = new URL(storedValue);
  } catch {
    throw invalidAccessoryImage();
  }
  if (
    url.origin !== new URL(supabaseUrl).origin || url.username || url.password
  ) {
    throw invalidAccessoryImage();
  }

  const markers = [
    `/storage/v1/object/${accessoryImageBucket}/`,
    `/storage/v1/object/public/${accessoryImageBucket}/`,
    `/storage/v1/object/sign/${accessoryImageBucket}/`,
    `/storage/v1/object/authenticated/${accessoryImageBucket}/`,
  ];
  const marker = markers.find((candidate) =>
    url.pathname.startsWith(candidate)
  );
  if (!marker) throw invalidAccessoryImage();

  let path: string;
  try {
    path = decodeURIComponent(url.pathname.slice(marker.length));
  } catch {
    throw invalidAccessoryImage();
  }
  return assertOwnedAccessoryPath(path, requiredPrefix);
}

function assertOwnedAccessoryPath(
  path: string,
  requiredPrefix: string,
): string {
  if (!path.startsWith(requiredPrefix)) {
    throw new EdgeError(
      403,
      "invalid_accessory_image_owner",
      "Accessory image must be in this accessory's owner namespace",
    );
  }
  return validatePath(path);
}

function validatePath(path: string): string {
  if (
    path.length > 500 ||
    path.includes("\\") ||
    path.split("/").some((part) => !part || part === "." || part === "..")
  ) {
    throw new EdgeError(
      422,
      "invalid_storage_path",
      "Storage object path is invalid",
    );
  }
  return path;
}

function invalidAccessoryImage(): EdgeError {
  return new EdgeError(
    422,
    "invalid_accessory_image",
    "Accessory image must be a canonical object in the accessory-images bucket",
  );
}
