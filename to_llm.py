import re
import argparse
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

def create_multi_component_context(component_names, start_path="."):
    """
    Creates an aggregate context file for one or more components, showing their intersection.
    
    Args:
        component_names (list): List of component names to analyze
        start_path (str): The starting directory to search from
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
        print(f"\nAnalyzing intersection of components: {', '.join(component_names)}")
    
    # Get links for all components
    component_data = {}
    all_linked_files = []
    
    for component_name in component_names:
        component_path, linked_paths = get_component_links(component_name, start_path)
        if component_path is None:
            print(f"Error: No markdown file found for component '{component_name}'.")
            return
        
        component_data[component_name] = {
            'path': component_path,
            'links': linked_paths
        }
        all_linked_files.append(linked_paths)
        print(f"Found {component_name}: {len(linked_paths)} linked files")
    
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
            if len(component_names) == 1:
                f_out.write(f"# Component: {component_names[0]}\n")
                f_out.write(f"\nLinked files: {len(union)}\n")
                # List all linked files at the top
                if union:
                    f_out.write(f"\n## All Linked Files\n")
                    for linked_path in sorted(union):
                        relative_linked_path = linked_path.relative_to(root_path)
                        f_out.write(f"- `{relative_linked_path}`\n")
            else:
                f_out.write(f"# Components: {', '.join(component_names)}\n")
                f_out.write(f"\nComponents analyzed: {len(component_names)}\n")
                f_out.write(f"Total linked files: {len(union)}\n")
                # List all linked files at the top
                if union:
                    f_out.write(f"\n## All Linked Files\n")
                    for linked_path in sorted(union):
                        relative_linked_path = linked_path.relative_to(root_path)
                        f_out.write(f"- `{relative_linked_path}`\n")
            
            # Write each component's main file
            for component_name in component_names:
                data = component_data[component_name]
                md_contents = data['path'].read_text(encoding="utf-8", errors="ignore")
                relative_path = data['path'].relative_to(root_path)
                
                f_out.write(f"\n\n---\n\n## Component: {component_name}\n")
                f_out.write(f"### Source File: `{relative_path}`\n\n")
                f_out.write(md_contents)
                
                print(f"  - Processed: {relative_path}")
            
            # Write union/linked files
            if union:
                if len(component_names) == 1:
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
                if len(component_names) == 1:
                    f_out.write("\n\n---\n\n## No Linked Files\n\nThis component has no linked documentation files.\n")
                else:
                    f_out.write("\n\n---\n\n## No Linked Files\n\nNo linked files found for any components.\n")
        
        if len(component_names) == 1:
            print(f"\nSuccessfully created context file: '{output_filename}'.")
        else:
            print(f"\nSuccessfully created context file: '{output_filename}.'")
    
    except IOError as e:
        print(f"Error writing to output file {output_filename}: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="""
NAME
    to_llm.py - aggregate TT-ISA component documentation for LLM analysis

SYNOPSIS
    python to_llm.py COMPONENT...

DESCRIPTION
    Aggregates component documentation files and their linked dependencies into
    a single context file for LLM analysis. Searches case-insensitively for
    component .md files and includes all directly linked markdown files.
    
    For multiple components, only shared/common linked files are included.

EXAMPLES
    python to_llm.py GMPOOL
        Creates gmpool_context.md with GMPOOL.md + all linked files
        
    python to_llm.py GMPOOL SFPADD
        Creates gmpool_sfpadd_context.md with both components + shared files
        
    python to_llm.py gmpool sfpadd
        Same as above (case insensitive)

OUTPUT
    Creates {component(s)}_context.md in current directory
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "component",
        type=str,
        nargs="+",
        metavar="COMPONENT",
        help="component name(s) to aggregate (case insensitive)"
    )
    import sys
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)
    
    args = parser.parse_args()

    # Always use multi-component logic (handles single components as list of one)
    create_multi_component_context(component_names=args.component)
