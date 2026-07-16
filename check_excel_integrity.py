#!/usr/bin/env python3
# ============================================================================
# Excel Data Integrity Check Script
# ============================================================================
# Compares two Excel files (XLS/XLSX) for data integrity.
# Automatically discovers sheets and columns, performs row-by-row and
# cell-by-cell comparison.
#
# USAGE:
#   python check_excel_integrity.py <source_excel> <target_excel> [options]
#
# OPTIONS:
#   --sheet NAME       Compare specific sheet (default: all sheets)
#   --output FILE      Generate HTML report
#   --verbose          Show detailed output
#   --help             Show this help message
#
# EXAMPLES:
#   python check_excel_integrity.py source.xlsx target.xlsx
#   python check_excel_integrity.py source.xlsx target.xlsx --sheet Sheet1
#   python check_excel_integrity.py source.xlsx target.xlsx --output report.html
# ============================================================================

import argparse
import sys
import os
from datetime import datetime
from typing import Dict, List, Tuple, Optional

try:
    import pandas as pd
except ImportError:
    print("ERROR: pandas is required. Install with: pip install pandas")
    sys.exit(1)

try:
    import openpyxl
except ImportError:
    print("ERROR: openpyxl is required. Install with: pip install openpyxl")
    sys.exit(1)

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

def parse_arguments():
    parser = argparse.ArgumentParser(
        description='Compare two Excel files for data integrity.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python check_excel_integrity.py source.xlsx target.xlsx
  python check_excel_integrity.py source.xlsx target.xlsx --sheet Sheet1
  python check_excel_integrity.py source.xlsx target.xlsx --output report.html
        """
    )
    parser.add_argument('source', help='Source Excel file path')
    parser.add_argument('target', help='Target Excel file path')
    parser.add_argument('--sheet', '-s', help='Specific sheet name to compare (default: all sheets)')
    parser.add_argument('--output', '-o', help='Output HTML report file path')
    parser.add_argument('--verbose', '-v', action='store_true', help='Show detailed output')
    return parser.parse_args()

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def normalize_value(value) -> str:
    """Normalize a value for comparison (handle None, empty, whitespace)."""
    if value is None or pd.isna(value):
        return 'NULL'
    if isinstance(value, str):
        return value.strip() if value.strip() else 'NULL'
    return str(value)

def get_excel_sheets(filepath: str) -> List[str]:
    """Get list of sheet names from an Excel file."""
    try:
        if filepath.lower().endswith('.xls'):
            # For XLS files, use xlrd (older format)
            return pd.read_excel(filepath, sheet_name=None).keys()
        else:
            # For XLSX files
            return pd.read_excel(filepath, sheet_name=None).keys()
    except Exception as e:
        print(f"ERROR: Could not read sheets from {filepath}: {e}")
        return []

def read_excel_sheet(filepath: str, sheet_name: str) -> pd.DataFrame:
    """Read a specific sheet from an Excel file."""
    try:
        df = pd.read_excel(filepath, sheet_name=sheet_name)
        return df
    except Exception as e:
        print(f"ERROR: Could not read sheet '{sheet_name}' from {filepath}: {e}")
        return pd.DataFrame()

# ============================================================================
# COMPARISON LOGIC
# ============================================================================

def compare_sheets(source_df: pd.DataFrame, target_df: pd.DataFrame, 
                   verbose: bool = False) -> Dict:
    """Compare two DataFrames and return comparison results."""
    results = {
        'source_rows': len(source_df),
        'target_rows': len(target_df),
        'matching_rows': 0,
        'mismatched_rows': 0,
        'source_only_rows': 0,
        'target_only_rows': 0,
        'mismatch_details': [],
        'column_mismatches': {}
    }
    
    # Get column names
    source_cols = list(source_df.columns)
    target_cols = list(target_df.columns)
    
    # Check column mismatch
    if source_cols != target_cols:
        results['column_mismatch'] = {
            'source': source_cols,
            'target': target_cols
        }
    
    # Normalize DataFrames for comparison
    source_normalized = source_df.fillna('NULL').astype(str)
    target_normalized = target_df.fillna('NULL').astype(str)
    
    # Find matching and mismatched rows
    matching_indices = []
    mismatched_indices = []
    source_only_indices = []
    target_only_indices = []
    
    # Compare row by row
    max_rows = max(len(source_normalized), len(target_normalized))
    
    for i in range(max_rows):
        if i >= len(source_normalized):
            # Only in target
            target_only_indices.append(i)
            if verbose:
                results['mismatch_details'].append({
                    'row': i + 1,
                    'type': 'TARGET_ONLY',
                    'source': None,
                    'target': target_normalized.iloc[i].to_dict() if i < len(target_normalized) else None
                })
        elif i >= len(target_normalized):
            # Only in source
            source_only_indices.append(i)
            if verbose:
                results['mismatch_details'].append({
                    'row': i + 1,
                    'type': 'SOURCE_ONLY',
                    'source': source_normalized.iloc[i].to_dict() if i < len(source_normalized) else None,
                    'target': None
                })
        else:
            # Compare cells
            source_row = source_normalized.iloc[i]
            target_row = target_normalized.iloc[i]
            
            row_mismatch = False
            cell_mismatches = []
            
            for col in source_cols:
                source_val = normalize_value(source_row.get(col))
                target_val = normalize_value(target_row.get(col))
                
                if source_val != target_val:
                    row_mismatch = True
                    cell_mismatches.append({
                        'column': col,
                        'source': source_val,
                        'target': target_val
                    })
            
            if row_mismatch:
                mismatched_indices.append(i)
                if verbose:
                    results['mismatch_details'].append({
                        'row': i + 1,
                        'type': 'MISMATCH',
                        'source': source_row.to_dict(),
                        'target': target_row.to_dict(),
                        'cell_mismatches': cell_mismatches
                    })
            else:
                matching_indices.append(i)
    
    # Update results
    results['matching_rows'] = len(matching_indices)
    results['mismatched_rows'] = len(mismatched_indices)
    results['source_only_rows'] = len(source_only_indices)
    results['target_only_rows'] = len(target_only_indices)
    
    # Column-by-column mismatch summary
    for col in source_cols:
        col_mismatches = 0
        for i in mismatched_indices:
            source_val = normalize_value(source_df.iloc[i].get(col))
            target_val = normalize_value(target_df.iloc[i].get(col))
            if source_val != target_val:
                col_mismatches += 1
        if col_mismatches > 0:
            results['column_mismatches'][col] = col_mismatches
    
    return results

def generate_text_report(sheet_name: str, results: Dict, verbose: bool = False) -> str:
    """Generate a text report for the comparison results."""
    lines = []
    
    lines.append("=" * 70)
    lines.append(f"EXCEL DATA INTEGRITY CHECK - Sheet: {sheet_name}")
    lines.append("=" * 70)
    lines.append("")
    
    # Row count summary
    lines.append("ROW COUNT SUMMARY")
    lines.append("-" * 17)
    lines.append(f"Source Rows:       {results['source_rows']}")
    lines.append(f"Target Rows:       {results['target_rows']}")
    lines.append("")
    
    # Data match summary
    lines.append("DATA MATCH SUMMARY")
    lines.append("-" * 18)
    lines.append(f"Matching Rows:     {results['matching_rows']}")
    lines.append(f"Mismatched Rows:   {results['mismatched_rows']}")
    lines.append(f"Rows in Source:    {results['source_only_rows']}")
    lines.append(f"Rows in Target:    {results['target_only_rows']}")
    lines.append("")
    
    # Column mismatch warning
    if 'column_mismatch' in results:
        lines.append("WARNING: Column mismatch detected!")
        lines.append(f"Source columns: {', '.join(results['column_mismatch']['source'])}")
        lines.append(f"Target columns: {', '.join(results['column_mismatch']['target'])}")
        lines.append("")
    
    # Detailed mismatch report
    if results['mismatch_details'] and verbose:
        lines.append("=" * 70)
        lines.append("DETAILED MISMATCH REPORT")
        lines.append("=" * 70)
        lines.append("")
        
        # Source only rows
        if results['source_only_rows'] > 0:
            lines.append(f"Rows Only in Source (up to 100):")
            lines.append("-" * 30)
            for detail in results['mismatch_details']:
                if detail['type'] == 'SOURCE_ONLY':
                    lines.append(f"Row {detail['row']}: {detail['source']}")
            lines.append("")
        
        # Target only rows
        if results['target_only_rows'] > 0:
            lines.append(f"Rows Only in Target (up to 100):")
            lines.append("-" * 30)
            for detail in results['mismatch_details']:
                if detail['type'] == 'TARGET_ONLY':
                    lines.append(f"Row {detail['row']}: {detail['target']}")
            lines.append("")
        
        # Mismatched rows
        if results['mismatched_rows'] > 0:
            lines.append(f"Mismatched Rows (up to 100):")
            lines.append("-" * 30)
            for detail in results['mismatch_details']:
                if detail['type'] == 'MISMATCH':
                    lines.append(f"Row {detail['row']}:")
                    for cm in detail.get('cell_mismatches', [])[:5]:  # Show first 5 mismatches
                        lines.append(f"  {cm['column']}: '{cm['source']}' != '{cm['target']}'")
            lines.append("")
    
    # Column-by-column summary
    if results['column_mismatches']:
        lines.append("=" * 70)
        lines.append("COLUMN-BY-COLUMN MISMATCH SUMMARY")
        lines.append("=" * 70)
        for col, count in results['column_mismatches'].items():
            lines.append(f"{col}: {count} mismatched cell(s)")
        lines.append("")
    
    lines.append("=" * 70)
    lines.append("END OF REPORT")
    lines.append("=" * 70)
    
    return "\n".join(lines)

def generate_html_report(all_sheets_results: Dict[str, Dict], 
                         source_file: str, target_file: str) -> str:
    """Generate an HTML report with color-coded differences."""
    html = """<!DOCTYPE html>
<html>
<head>
    <title>Excel Data Integrity Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        h2 { color: #666; margin-top: 20px; }
        .summary { background: #f5f5f5; padding: 10px; border-radius: 5px; }
        .match { background: #d4edda; }
        .mismatch { background: #f8d7da; }
        .warning { background: #fff3cd; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background: #4CAF50; color: white; }
        .source-val { color: #0066cc; }
        .target-val { color: #cc0000; }
        .match-val { color: #006600; }
    </style>
</head>
<body>
    <h1>Excel Data Integrity Report</h1>
    <p><strong>Source:</strong> """ + source_file + """</p>
    <p><strong>Target:</strong> """ + target_file + """</p>
    <p><strong>Generated:</strong> """ + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + """</p>
    
"""
    
    for sheet_name, results in all_sheets_results.items():
        html += f"""
    <h2>Sheet: {sheet_name}</h2>
    <div class="summary">
        <p><strong>Source Rows:</strong> {results['source_rows']}</p>
        <p><strong>Target Rows:</strong> {results['target_rows']}</p>
        <p><strong>Matching Rows:</strong> {results['matching_rows']}</p>
        <p><strong>Mismatched Rows:</strong> {results['mismatched_rows']}</p>
        <p><strong>Rows in Source Only:</strong> {results['source_only_rows']}</p>
        <p><strong>Rows in Target Only:</strong> {results['target_only_rows']}</p>
    </div>
"""
    
    html += """
</body>
</html>"""
    
    return html

# ============================================================================
# MAIN FUNCTION
# ============================================================================

def main():
    args = parse_arguments()
    
    # Validate input files
    if not os.path.exists(args.source):
        print(f"ERROR: Source file '{args.source}' not found.")
        sys.exit(1)
    
    if not os.path.exists(args.target):
        print(f"ERROR: Target file '{args.target}' not found.")
        sys.exit(1)
    
    # Get sheet names
    source_sheets = get_excel_sheets(args.source)
    target_sheets = get_excel_sheets(args.target)
    
    if not source_sheets or not target_sheets:
        print("ERROR: Could not read Excel files.")
        sys.exit(1)
    
    # Determine sheets to compare
    if args.sheet:
        sheets_to_compare = [args.sheet]
        if args.sheet not in source_sheets:
            print(f"WARNING: Sheet '{args.sheet}' not found in source file.")
        if args.sheet not in target_sheets:
            print(f"WARNING: Sheet '{args.sheet}' not found in target file.")
    else:
        # Compare all sheets that exist in both files
        sheets_to_compare = list(set(source_sheets) & set(target_sheets))
        if not sheets_to_compare:
            print("WARNING: No common sheets found between source and target files.")
            sheets_to_compare = list(source_sheets)  # Fall back to source sheets
    
    # Compare each sheet
    all_results = {}
    
    print("=" * 70)
    print("EXCEL DATA INTEGRITY CHECK")
    print("=" * 70)
    print(f"Source File: {args.source}")
    print(f"Target File: {args.target}")
    print(f"Report Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)
    print()
    
    for sheet in sheets_to_compare:
        print(f"Comparing sheet: {sheet}")
        print("-" * 40)
        
        source_df = read_excel_sheet(args.source, sheet)
        target_df = read_excel_sheet(args.target, sheet)
        
        if source_df.empty or target_df.empty:
            print(f"WARNING: Could not read sheet '{sheet}' from one or both files.")
            continue
        
        results = compare_sheets(source_df, target_df, args.verbose)
        all_results[sheet] = results
        
        # Print text report
        print(generate_text_report(sheet, results, args.verbose))
        print()
    
    # Generate HTML report if requested
    if args.output:
        html_report = generate_html_report(all_results, args.source, args.target)
        with open(args.output, 'w') as f:
            f.write(html_report)
        print(f"HTML report saved to: {args.output}")
    
    print("=" * 70)
    print("COMPARISON COMPLETE")
    print("=" * 70)

if __name__ == '__main__':
    main()