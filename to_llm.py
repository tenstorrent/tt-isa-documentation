import re
import argparse
import sys
from pathlib import Path

def get_component_links(component_name, start_path="."):
    """
    Gets the links for a single component.
    Returns a tuple of (component_path, linked_paths_set) or (None, None).
    """
    root_path = Path(start_path).resolve()
    try:
        # Find the first matching markdown file, excluding generated context files.
        component_path = next(
            (p for p in root_path.rglob("*.md")
             if component_name.lower() in p.name.lower() and not p.name.endswith("_context.md")),
            None
        )
        if not component_path:
            return None, None

        md_contents = component_path.read_text(encoding="utf-8", errors="ignore")
        
        # Find all relative markdown links.
        md_links = re.findall(r'\[[^\]]*\]\((?!https?://)([^#)]*\.md)', md_contents)
        
        # Resolve and filter for existing files.
        linked_paths = {
            resolved_path
            for link in md_links
            if (resolved_path := (component_path.parent / link).resolve()).exists()
        }
        return component_path, linked_paths
    except Exception:
        # Broad exception to catch any file or parsing errors.
        return None, None

def extract_instructions_from_code(code_text):
    """
    Extracts unique instruction names (TT_OP_*, TTI_*) from code.
    """
    patterns = [r'TT_OP_([A-Z][A-Z0-9_]*)', r'TTI_([A-Z][A-Z0-9_]*)']
    instructions = set()
    for pattern in patterns:
        instructions.update(m.upper() for m in re.findall(pattern, code_text, re.IGNORECASE))
    return sorted(instructions)

def from_llk_mode():
    """
    Interactive mode to extract instructions from stdin and generate context.
    """
    print("Interactive mode: Extract TT instructions from code")
    print("=" * 50)
    print("Paste or type your code below, then press:")
    print("  • Ctrl+D (Linux/Mac) or Ctrl+Z (Windows) to finish")
    print("  • Or pipe code: cat myfile.c | python to_llm.py --from-llk")
    print()
    print("Looking for instructions with prefixes: TT_OP_, TTI_")
    print("=" * 50)

    try:
        code_text = sys.stdin.read()
        if not code_text.strip():
            print("No code provided.")
            sys.exit(1)
    except KeyboardInterrupt:
        print("\nOperation cancelled.")
        sys.exit(1)

    print(f"\n{'=' * 60}\nAnalyzing code...")
    instructions = extract_instructions_from_code(code_text)

    if not instructions:
        print("No instructions found with TT_OP_ or TTI_ prefixes.")
        sys.exit(1)

    print(f"Found {len(instructions)} unique instructions: {', '.join(instructions)}")
    print("\nCreating multi-component context for these instructions...")
    create_multi_component_context(component_names=instructions, input_code=code_text)

def create_multi_component_context(component_names, start_path=".", input_code=None):
    """
    Creates an aggregate context file for one or more components.
    """
    root_path = Path(start_path).resolve()
    
    # --- 1. Gather Component Data ---
    component_data = {}
    missing_components = []
    for name in component_names:
        path, links = get_component_links(name, start_path)
        if path:
            component_data[name] = {'path': path, 'links': links}
            print(f"Found {name}: {len(links)} linked files")
        else:
            print(f"Warning: No markdown file found for component '{name}' - skipping")
            missing_components.append(name)

    if not component_data:
        print(f"Error: No documentation found for any requested components: {', '.join(component_names)}")
        return

    # --- 2. Prepare Content ---
    found_names = list(component_data.keys())
    all_links = [d['links'] for d in component_data.values()]
    union_links = set.union(*all_links) if all_links else set()

    is_single = len(found_names) == 1
    title_prefix = "Component" if is_single else "Components"
    output_filename = Path(f"{'_'.join(name.lower() for name in found_names)}_context.md")

    print(f"\nAnalyzing {'component' if is_single else 'union of components'}: {', '.join(found_names)}")
    if not is_single:
        print(f"Union: {len(union_links)} total unique linked files")

    # --- 3. Write Output File ---
    try:
        with open(output_filename, "w", encoding="utf-8") as f_out:
            # --- Header ---
            f_out.write(f"# {title_prefix}: {', '.join(found_names)}\n")
            if is_single:
                f_out.write(f"\nLinked files: {len(union_links)}\n")
            else:
                f_out.write(f"\nComponents analyzed: {len(found_names)}\n")
                f_out.write(f"Total linked files: {len(union_links)}\n")

            if missing_components:
                f_out.write(f"\n**Note:** The following components were not found: {', '.join(missing_components)}\n")

            if input_code:
                f_out.write(f"\n## Input Code\n\n```c\n{input_code.strip()}\n```\n")

            # --- Linked Files List ---
            if union_links:
                f_out.write("\n## All Linked Files\n")
                for path in sorted(union_links):
                    f_out.write(f"- `{path.relative_to(root_path)}`\n")

            # --- Main Component Content ---
            for name, data in component_data.items():
                content = data['path'].read_text(encoding="utf-8", errors="ignore")
                relative_path = data['path'].relative_to(root_path)
                f_out.write(f"\n\n---\n\n## Component: {name}\n")
                f_out.write(f"### Source File: `{relative_path}`\n\n{content}")
                print(f"  - Processed: {relative_path}")

            # --- Linked Files Content ---
            if union_links:
                header_prefix = "Linked" if is_single else "All Linked"
                f_out.write(f"\n\n---\n\n## {header_prefix} Files Content\n")
                for path in sorted(union_links):
                    try:
                        content = path.read_text(encoding="utf-8", errors="ignore")
                        relative_path = path.relative_to(root_path)
                        f_out.write(f"\n\n---\n\n### {header_prefix} Source: `{relative_path}`\n\n{content}")
                        print(f"  - Processed {header_prefix.lower()}: {relative_path}")
                    except Exception as e:
                        print(f"  - Error reading linked file {path}: {e}")
            else:
                f_out.write("\n\n---\n\n## No Linked Files\n\nThis component has no linked documentation files.\n")

        print(f"\nSuccessfully created context file: '{output_filename}'.")
        if missing_components:
            print(f"Warning: {len(missing_components)} component(s) not found: {', '.join(missing_components)}")

    except IOError as e:
        print(f"Error writing to output file {output_filename}: {e}")


def main():
    """Main function to parse arguments and run the script."""
    parser = argparse.ArgumentParser(
        description="Aggregates TT-ISA component documentation for LLM analysis.",
        epilog="""
EXAMPLES
    python to_llm.py GMPOOL
        Creates gmpool_context.md with GMPOOL.md + all linked files
        
    python to_llm.py GMPOOL SFPADD
        Creates gmpool_sfpadd_context.md with both components + all linked files
        
    python to_llm.py --from-llk
        Enters interactive mode to paste code.
        Extracts TT_OP_ and TTI_ instructions and creates a context file.
        (Finish input with Ctrl+D on Linux/Mac or Ctrl+Z on Windows)
""",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--from-llk",
        action="store_true",
        help="Interactive mode to extract instructions from code. Can be piped, e.g., 'cat file.c | %(prog)s --from-llk'"
    )
    parser.add_argument(
        "component",
        type=str,
        nargs="*",
        metavar="COMPONENT",
        help="Component name(s) to aggregate (case insensitive)"
    )
    
    args = parser.parse_args()

    if args.from_llk and args.component:
        parser.error("argument component: not allowed with argument --from-llk")
    
    if not args.from_llk and not args.component:
        parser.print_help()
        sys.exit(1)

    if args.from_llk:
        from_llk_mode()
    else:
        create_multi_component_context(component_names=args.component)

if __name__ == "__main__":
    main()