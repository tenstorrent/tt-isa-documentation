import re
import argparse
import sys
from pathlib import Path

def get_component_links(component_name, start_path="."):
    """
    Gets the links for a single component.
    
    Returns:
        tuple: (component_path, linked_paths_set) or (None, None) if not found
    """
    root_path = Path(start_path).resolve()
    
    try:
        # Exclude previously generated output files from the search (case insensitive)
        all_matches = [p for p in root_path.rglob("*.md") if component_name.lower() in p.name.lower() and not p.name.endswith("_context.md")]
        if not all_matches:
            return None, None
        
        component_path = all_matches[0]
        md_contents = component_path.read_text(encoding="utf-8", errors="ignore")
        
        # Find linked markdown files
        md_links = re.findall(r'\[[^\]]*\]\((?!https?://)([^#)]*\.md)', md_contents)
        linked_paths = set()
        
        for link in md_links:
            linked_md_path = (component_path.parent / link).resolve()
            if linked_md_path.exists():
                linked_paths.add(linked_md_path)
        
        return component_path, linked_paths
    except Exception:
        return None, None

def extract_instructions_from_code(code_text):
    """
    Extracts instruction names from code that start with TT_OP_ or TTI_.
    
    Args:
        code_text (str): The code text to scan for instructions
        
    Returns:
        list: List of unique instruction names (without TT_OP_/TTI_ prefixes)
    """
    # Pattern to match TT_OP_ and TTI_ prefixes followed by instruction names
    # This captures the instruction name part after the prefix
    patterns = [
        r'TT_OP_([A-Z][A-Z0-9_]*)',  # TT_OP_INSTRUCTION_NAME
        r'TTI_([A-Z][A-Z0-9_]*)'     # TTI_INSTRUCTION_NAME
    ]
    
    instructions = set()
    
    for pattern in patterns:
        matches = re.findall(pattern, code_text, re.IGNORECASE)
        for match in matches:
            # Convert to proper case for component lookup
            instructions.add(match.upper())
    
    return sorted(list(instructions))

def from_llk_mode():
    """
    Interactive mode to paste code and extract instruction names.
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
        # Read multiple lines from stdin until EOF
        lines = []
        while True:
            try:
                line = input()
                lines.append(line)
            except EOFError:
                break
    except KeyboardInterrupt:
        print("\nOperation cancelled.")
        sys.exit(1)
    
    code_text = '\n'.join(lines)
    
    if not code_text.strip():
        print("No code provided.")
        sys.exit(1)
    
    print(f"\n{'=' * 60}")
    print("Analyzing code...")
    
    # Extract instruction names
    instructions = extract_instructions_from_code(code_text)
    
    if not instructions:
        print("No instructions found with TT_OP_ or TTI_ prefixes.")
        sys.exit(1)
    
    print(f"Found {len(instructions)} unique instructions:")
    for instr in instructions:
        print(f"  - {instr}")
    
    print(f"\nCreating multi-component context for these instructions...")
    
    # Create multi-component context with the original input code
    create_multi_component_context(component_names=instructions, input_code=code_text)

def create_multi_component_context(component_names, start_path=".", input_code=None):
    """
    Creates an aggregate context file for one or more components, showing their intersection.
    
    Args:
        component_names (list): List of component names to analyze
        start_path (str): The starting directory to search from
        input_code (str, optional): Original input code to include at top of output
    """
    root_path = Path(start_path).resolve()
    
    # Handle single component case with simpler filename
    if len(component_names) == 1:
        output_filename = Path(f"{component_names[0].lower()}_context.md")
    else:
        components_str = "_".join([name.lower() for name in component_names])
        output_filename = Path(f"{components_str}_context.md")
    
    if len(component_names) == 1:
        print(f"\nAnalyzing component: {component_names[0]}")
    else:
        print(f"\nAnalyzing union of components: {', '.join(component_names)}")
    
    # Get links for all components
    component_data = {}
    all_linked_files = []
    missing_components = []
    
    for component_name in component_names:
        component_path, linked_paths = get_component_links(component_name, start_path)
        if component_path is None:
            print(f"Warning: No markdown file found for component '{component_name}' - skipping")
            missing_components.append(component_name)
            continue
        
        component_data[component_name] = {
            'path': component_path,
            'links': linked_paths
        }
        all_linked_files.append(linked_paths)
        print(f"Found {component_name}: {len(linked_paths)} linked files")
    
    # Check if we have any valid components
    if not component_data:
        print(f"Error: No documentation found for any of the requested components: {', '.join(component_names)}")
        return
    
    # Update component_names to only include found components
    found_component_names = list(component_data.keys())
    
    # Find union of linked files (all unique files across components)
    if len(all_linked_files) > 1:
        union = set.union(*all_linked_files)
        print(f"\nUnion: {len(union)} total unique linked files")
    elif len(all_linked_files) == 1:
        union = all_linked_files[0]  # For single component, all its links
        print(f"\nLinked files: {len(union)} files")
    else:
        union = set()
    
    # Create output file
    try:
        with open(output_filename, "w", encoding="utf-8") as f_out:
            if len(found_component_names) == 1:
                f_out.write(f"# Component: {found_component_names[0]}\n")
                f_out.write(f"\nLinked files: {len(union)}\n")
            else:
                f_out.write(f"# Components: {', '.join(found_component_names)}\n")
                f_out.write(f"\nComponents analyzed: {len(found_component_names)}\n")
                f_out.write(f"Total linked files: {len(union)}\n")
            
            # Report missing components if any
            if missing_components:
                f_out.write(f"\n**Note:** The following components were not found: {', '.join(missing_components)}\n")
            
            # Include input code if provided (from --from-llk mode)
            if input_code:
                f_out.write(f"\n## Input Code\n\n")
                f_out.write(f"```c\n{input_code.strip()}\n```\n")
            
            # List all linked files at the top
            if union:
                f_out.write(f"\n## All Linked Files\n")
                for linked_path in sorted(union):
                    relative_linked_path = linked_path.relative_to(root_path)
                    f_out.write(f"- `{relative_linked_path}`\n")
            
            # Write each component's main file
            for component_name in found_component_names:
                data = component_data[component_name]
                md_contents = data['path'].read_text(encoding="utf-8", errors="ignore")
                relative_path = data['path'].relative_to(root_path)
                
                f_out.write(f"\n\n---\n\n## Component: {component_name}\n")
                f_out.write(f"### Source File: `{relative_path}`\n\n")
                f_out.write(md_contents)
                
                print(f"  - Processed: {relative_path}")
            
            # Write union/linked files
            if union:
                if len(found_component_names) == 1:
                    f_out.write("\n\n---\n\n## Linked Files\n")
                    header_prefix = "Linked"
                else:
                    f_out.write("\n\n---\n\n## All Linked Files\n")
                    header_prefix = "Linked"
                
                for linked_path in sorted(union):
                    try:
                        linked_contents = linked_path.read_text(encoding="utf-8", errors="ignore")
                        relative_linked_path = linked_path.relative_to(root_path)
                        f_out.write(f"\n\n---\n\n### {header_prefix} Source: `{relative_linked_path}`\n\n")
                        f_out.write(linked_contents)
                        print(f"  - Processed {header_prefix}: {relative_linked_path}")
                    except Exception as e:
                        print(f"  - Error reading {header_prefix.lower()} file {linked_path}: {e}")
            else:
                if len(found_component_names) == 1:
                    f_out.write("\n\n---\n\n## No Linked Files\n\nThis component has no linked documentation files.\n")
                else:
                    f_out.write("\n\n---\n\n## No Linked Files\n\nNo linked files found for any components.\n")
        
        if len(found_component_names) == 1:
            print(f"\nSuccessfully created context file: '{output_filename}'.")
        else:
            print(f"\nSuccessfully created context file: '{output_filename}.'")
        
        # Report summary of what was processed
        if missing_components:
            print(f"Warning: {len(missing_components)} component(s) not found: {', '.join(missing_components)}")
    
    except IOError as e:
        print(f"Error writing to output file {output_filename}: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="""
NAME
    to_llm.py - aggregate TT-ISA component documentation for LLM analysis

SYNOPSIS
    python to_llm.py COMPONENT...
    python to_llm.py --from-llk

DESCRIPTION
    Aggregates component documentation files and their linked dependencies into
    a single context file for LLM analysis. Searches case-insensitively for
    component .md files and includes all directly linked markdown files.
    
    For multiple components, all unique linked files are included.

EXAMPLES
    python to_llm.py GMPOOL
        Creates gmpool_context.md with GMPOOL.md + all linked files
        
    python to_llm.py GMPOOL SFPADD
        Creates gmpool_sfpadd_context.md with both components + all linked files
        
    python to_llm.py gmpool sfpadd
        Same as above (case insensitive)
        
    python to_llm.py --from-llk
        Interactive mode: paste code, extract TT_OP_/TTI_ instructions, create context

OUTPUT
    Creates {component(s)}_context.md in current directory
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        "--from-llk",
        action="store_true",
        help="Interactive mode to extract instructions from pasted code"
    )
    
    parser.add_argument(
        "component",
        type=str,
        nargs="*",
        metavar="COMPONENT",
        help="component name(s) to aggregate (case insensitive)"
    )
    
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)
    
    args = parser.parse_args()
    
    # Handle --from-llk mode
    if args.from_llk:
        if args.component:
            print("Error: Cannot specify components when using --from-llk mode")
            sys.exit(1)
        from_llk_mode()
    else:
        if not args.component:
            print("Error: Must specify at least one component or use --from-llk")
            parser.print_help()
            sys.exit(1)
        # Always use multi-component logic (handles single components as list of one)
        create_multi_component_context(component_names=args.component)
