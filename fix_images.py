import re
import os

files = [
    "lib/screens/catalog_screen.dart",
    "lib/screens/product_screen.dart",
    "lib/screens/profile_screen.dart",
    "lib/screens/outfits_screen.dart",
    "lib/screens/create_outfit_screen.dart",
    "lib/screens/publish_outfit_screen.dart",
]

for filepath in files:
    if not os.path.exists(filepath):
        print(f"SKIP: {filepath}")
        continue

    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Remove ALL duplicate app_image.dart import lines, keep only one
    content = re.sub(
        r"(import\s+['\"]\.\.\.?/widgets/app_image\.dart['\"];\n)+",
        "import '../widgets/app_image.dart';\n",
        content,
    )

    # 2. If no import at all, add after last import line
    if "import '../widgets/app_image.dart';" not in content:
        lines = content.split("\n")
        last_import = -1
        for i, line in enumerate(lines):
            if line.strip().startswith("import "):
                last_import = i
        if last_import >= 0:
            lines.insert(last_import + 1, "import '../widgets/app_image.dart';")
            content = "\n".join(lines)

    # 3. Replace Image.asset(...) with AppImage(imageUrl: ...)
    def replace_img(match):
        args = match.group(1)
        depth = 0
        in_str = False
        str_char = None
        first_comma = -1
        for i, c in enumerate(args):
            if not in_str and c in "'\":
                in_str = True
                str_char = c
            elif in_str and c == str_char:
                if i > 0 and args[i-1] != "\\":
                    in_str = False
                    str_char = None
            elif not in_str and c == "(":
                depth += 1
            elif not in_str and c == ")":
                depth -= 1
            elif not in_str and c == "," and depth == 0:
                first_comma = i
                break

        if first_comma >= 0:
            path_arg = args[:first_comma].strip()
            rest = args[first_comma + 1 :].strip()
            # Remove errorBuilder from rest
            rest = re.sub(r",?\s*errorBuilder:\s*\([^)]*\)\s*=>\s*[^,]+", "", rest)
            rest = re.sub(r",?\s*errorBuilder:\s*\([^)]*\)\s*\{[^}]*\}", "", rest)
            if rest:
                return "AppImage(imageUrl: " + path_arg + ", " + rest + ")"
            else:
                return "AppImage(imageUrl: " + path_arg + ")"
        else:
            return "AppImage(imageUrl: " + args.strip() + ")"

    content = re.sub(
        r"Image\.asset\(([^)]+)\)", replace_img, content, flags=re.DOTALL
    )

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)

    # Verify
    with open(filepath, "r", encoding="utf-8") as f:
        check = f.read()
    import_count = check.count("import '../widgets/app_image.dart';")
    remaining = check.count("Image.asset")
    appimg = check.count("AppImage")
    print(
        filepath
        + ": imports="
        + str(import_count)
        + ", Image.asset="
        + str(remaining)
        + ", AppImage="
        + str(appimg)
    )
