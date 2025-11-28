#!/usr/bin/env python3
"""
Visualize the Antarctic grid system structure
Creates diagrams showing tile hierarchy and nesting
"""

import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.patches import Rectangle
import numpy as np

# Create figure with subplots
fig = plt.figure(figsize=(16, 10))
fig.suptitle('Antarctic Territory Grid System - Design Overview', 
             fontsize=16, fontweight='bold', y=0.98)

# ============================================================================
# Subplot 1: L1 and L2 Grid Concept
# ============================================================================
ax1 = plt.subplot(2, 3, 1)
ax1.set_title('Grid Hierarchy Concept', fontsize=12, fontweight='bold')
ax1.set_aspect('equal')
ax1.set_xlim(0, 36)
ax1.set_ylim(0, 36)
ax1.set_xlabel('Distance (km)', fontsize=10)
ax1.set_ylabel('Distance (km)', fontsize=10)

# Draw L1 tile
l1_rect = Rectangle((0, 0), 36, 36, linewidth=3, edgecolor='darkblue', 
                     facecolor='lightblue', alpha=0.3)
ax1.add_patch(l1_rect)
ax1.text(18, 37.5, 'L1 Tile: 36 km × 36 km', ha='center', fontsize=11, 
         fontweight='bold', color='darkblue')
ax1.text(18, -2, '600×600 pixels @ 60m/px', ha='center', fontsize=9, 
         style='italic', color='darkblue')

# Draw L2 grid (6x6)
for i in range(6):
    for j in range(6):
        x, y = i * 6, j * 6
        l2_rect = Rectangle((x, y), 6, 6, linewidth=0.8, edgecolor='darkgreen', 
                           facecolor='lightgreen', alpha=0.2)
        ax1.add_patch(l2_rect)

# Highlight one L2 tile
highlight_rect = Rectangle((12, 18), 6, 6, linewidth=2, edgecolor='red', 
                          facecolor='yellow', alpha=0.4)
ax1.add_patch(highlight_rect)
ax1.text(15, 21, 'L2', ha='center', va='center', fontsize=9, 
         fontweight='bold', color='darkred')

# Add grid labels
ax1.text(3, 33, 'L2 tiles: 6 km × 6 km', fontsize=9, color='darkgreen')
ax1.text(3, 31, '600×600 px @ 10m/px', fontsize=8, style='italic', 
         color='darkgreen')

# Add nesting annotation
ax1.annotate('6 × 6 = 36 L2 tiles\nper L1 tile', xy=(30, 3), xytext=(28, 8),
            fontsize=9, ha='center', bbox=dict(boxstyle='round', fc='wheat'),
            arrowprops=dict(arrowstyle='->', lw=1.5))

ax1.grid(True, alpha=0.2)

# ============================================================================
# Subplot 2: Tile Indexing Example
# ============================================================================
ax2 = plt.subplot(2, 3, 2)
ax2.set_title('Tile Index System', fontsize=12, fontweight='bold')
ax2.set_aspect('equal')
ax2.set_xlim(-0.5, 6.5)
ax2.set_ylim(-0.5, 6.5)
ax2.set_xlabel('Column Index', fontsize=10)
ax2.set_ylabel('Row Index', fontsize=10)

# Draw L2 tiles with indices
colors = plt.cm.viridis(np.linspace(0, 1, 36))
idx = 0
for row in range(6):
    for col in range(6):
        rect = Rectangle((col, row), 1, 1, linewidth=1, edgecolor='black', 
                        facecolor=colors[idx], alpha=0.5)
        ax2.add_patch(rect)
        ax2.text(col + 0.5, row + 0.5, f'{col},{row}', ha='center', va='center',
                fontsize=7, fontweight='bold')
        idx += 1

# Highlight relationship
highlight_cols = [2, 3]
highlight_rows = [3, 4]
for col in highlight_cols:
    for row in highlight_rows:
        rect = Rectangle((col, row), 1, 1, linewidth=2.5, edgecolor='red', 
                        facecolor='none')
        ax2.add_patch(rect)

# Add L1 parent annotation
ax2.text(3.3, 6.7, 'Example: L2 tiles (2-3, 3-4)', fontsize=9, ha='center',
         bbox=dict(boxstyle='round', fc='yellow', alpha=0.7))
ax2.text(3.3, -1, '→ Parent L1: col=0, row=0', fontsize=9, ha='center',
         style='italic', color='darkred')

ax2.set_xticks(range(7))
ax2.set_yticks(range(7))
ax2.grid(True, alpha=0.3)

# ============================================================================
# Subplot 3: Tile ID Format
# ============================================================================
ax3 = plt.subplot(2, 3, 3)
ax3.axis('off')
ax3.set_title('Tile Identification Format', fontsize=12, fontweight='bold')

# Create tile ID breakdown
y_pos = 0.85
ax3.text(0.5, y_pos, '43S_L1_0006_0114', ha='center', fontsize=18, 
         fontweight='bold', family='monospace',
         bbox=dict(boxstyle='round', fc='lightblue', ec='darkblue', lw=2))

# Component breakdown
y_pos = 0.65
components = [
    ('43S', 'UTM Zone', 'Zone 43, Southern Hemisphere'),
    ('L1', 'Grid Level', 'Level 1 (36km tiles)'),
    ('0006', 'Column', 'Column index from origin'),
    ('0114', 'Row', 'Row index from origin')
]

for i, (part, label, desc) in enumerate(components):
    y = y_pos - i * 0.15
    ax3.text(0.15, y, part, fontsize=14, fontweight='bold', family='monospace',
            bbox=dict(boxstyle='round', fc='wheat', ec='black'))
    ax3.text(0.35, y, f'← {label}', fontsize=11, va='center')
    ax3.text(0.35, y-0.03, desc, fontsize=8, style='italic', va='top', 
            color='gray')

# Add example conversion
ax3.text(0.5, 0.05, 'Example tile contains point at:', ha='center', 
         fontsize=10, fontweight='bold')
ax3.text(0.5, -0.02, 'UTM: 399,338 E, 4,126,677 N', ha='center', 
         fontsize=9, family='monospace')
ax3.text(0.5, -0.08, 'Lon/Lat: 73.5°E, 53.0°S', ha='center', 
         fontsize=9, family='monospace')

# ============================================================================
# Subplot 4: UTM Zone Coverage
# ============================================================================
ax4 = plt.subplot(2, 3, 4)
ax4.set_title('UTM Zone Coverage (AAT)', fontsize=12, fontweight='bold')
ax4.set_xlabel('Longitude (°E)', fontsize=10)
ax4.set_ylabel('Latitude (°S)', fontsize=10)
ax4.set_xlim(40, 165)
ax4.set_ylim(-72, -48)

# Draw zone boundaries (simplified)
zones = range(42, 59)
for z in zones:
    lon_min = -183 + z * 6
    lon_max = lon_min + 6
    
    # Zone rectangle
    if 44 <= lon_min <= 160 or 44 <= lon_max <= 160:
        color = 'lightblue' if z % 2 == 0 else 'lightgreen'
        rect = Rectangle((max(lon_min, 40), -70), 
                        min(6, 165 - max(lon_min, 40)), 20,
                        facecolor=color, edgecolor='black', 
                        linewidth=0.5, alpha=0.4)
        ax4.add_patch(rect)
        
        # Zone label
        if 44 <= lon_min + 3 <= 160:
            ax4.text(lon_min + 3, -71, f'{z}S', ha='center', fontsize=8,
                    fontweight='bold')

# Mark key locations
locations = [
    (73.5, -53.0, 'Heard Is.', 'red'),
    (158.85, -54.6, 'Macquarie Is.', 'red'),
    (77.97, -68.58, 'Davis Stn', 'blue')
]

for lon, lat, name, color in locations:
    ax4.plot(lon, lat, 'o', color=color, markersize=8, markeredgecolor='black')
    ax4.text(lon, lat - 1.5, name, ha='center', fontsize=8, 
            bbox=dict(boxstyle='round', fc='white', alpha=0.8))

# Add AAT boundary
ax4.axvline(44, color='darkred', linewidth=2, linestyle='--', alpha=0.7, 
           label='AAT Boundaries')
ax4.axvline(160, color='darkred', linewidth=2, linestyle='--', alpha=0.7)

# Add latitude limit
ax4.axhline(-70, color='orange', linewidth=2, linestyle=':', alpha=0.7,
           label='UTM Limit (~70°S)')

ax4.grid(True, alpha=0.3)
ax4.legend(loc='upper right', fontsize=8)

# ============================================================================
# Subplot 5: Resolution Comparison
# ============================================================================
ax5 = plt.subplot(2, 3, 5)
ax5.set_title('Resolution Levels', fontsize=12, fontweight='bold')
ax5.axis('off')

# Create comparison boxes
levels = [
    ('L1', '60 m/pixel', '36 km × 36 km', '600 × 600 px', 
     'Regional overview\nBroad coverage', 'lightblue'),
    ('L2', '10 m/pixel', '6 km × 6 km', '600 × 600 px', 
     'Detailed analysis\nHigh resolution', 'lightgreen')
]

for i, (level, res, size, dims, use, color) in enumerate(levels):
    y = 0.7 - i * 0.4
    
    # Box
    rect = patches.FancyBboxPatch((0.05, y - 0.15), 0.9, 0.25,
                                 boxstyle="round,pad=0.02",
                                 facecolor=color, edgecolor='black',
                                 linewidth=2, alpha=0.5,
                                 transform=ax5.transAxes)
    ax5.add_patch(rect)
    
    # Content
    ax5.text(0.15, y + 0.05, level, fontsize=20, fontweight='bold',
            transform=ax5.transAxes)
    ax5.text(0.5, y + 0.05, f'{res}', fontsize=14, fontweight='bold',
            transform=ax5.transAxes)
    ax5.text(0.5, y - 0.02, f'{size}', fontsize=11,
            transform=ax5.transAxes)
    ax5.text(0.5, y - 0.08, f'{dims}', fontsize=10, style='italic',
            transform=ax5.transAxes, color='gray')
    ax5.text(0.88, y, use, fontsize=9, ha='right', va='center',
            transform=ax5.transAxes, style='italic')

# Add comparison
ax5.text(0.5, 0.15, 'Same pixel count per tile → Same display size',
        ha='center', fontsize=10, fontweight='bold', style='italic',
        transform=ax5.transAxes, 
        bbox=dict(boxstyle='round', fc='yellow', alpha=0.5))

# ============================================================================
# Subplot 6: Design Principles
# ============================================================================
ax6 = plt.subplot(2, 3, 6)
ax6.set_title('Design Principles', fontsize=12, fontweight='bold')
ax6.axis('off')

principles = [
    '✓ Consistent Coverage',
    '  • Edge-to-edge tiling',
    '  • No gaps or overlaps within zones',
    '',
    '✓ Clean Nesting',
    '  • 6×6 L2 tiles per L1 tile',
    '  • Simple parent-child relationships',
    '',
    '✓ Sentinel-2 Alignment',
    '  • Compatible grid origins',
    '  • Integration with satellite data',
    '',
    '✓ Human-Viewable',
    '  • 600×600 pixel images',
    '  • Practical file sizes',
    '',
    '✓ Zone-Based',
    '  • Minimal distortion per zone',
    '  • Standard UTM projections'
]

y = 0.95
for line in principles:
    if line.startswith('✓'):
        ax6.text(0.05, y, line, fontsize=11, fontweight='bold',
                transform=ax6.transAxes, color='darkgreen')
    elif line.startswith('  •'):
        ax6.text(0.1, y, line, fontsize=9,
                transform=ax6.transAxes, color='darkblue')
    else:
        ax6.text(0.05, y, line, fontsize=9,
                transform=ax6.transAxes)
    y -= 0.05

plt.tight_layout()
plt.savefig('/mnt/user-data/outputs/grid_system_overview.png', 
           dpi=300, bbox_inches='tight', facecolor='white')
print("Grid system overview diagram saved!")

# Create a second figure showing the nesting detail
fig2, ax = plt.subplots(1, 1, figsize=(10, 10))
ax.set_title('L1/L2 Tile Nesting Detail\n(One L1 tile = 6×6 L2 tiles)', 
            fontsize=14, fontweight='bold', pad=20)
ax.set_aspect('equal')
ax.set_xlim(-1, 37)
ax.set_ylim(-1, 37)
ax.set_xlabel('Distance from origin (km)', fontsize=11)
ax.set_ylabel('Distance from origin (km)', fontsize=11)

# Draw L1 boundary
l1_outer = Rectangle((0, 0), 36, 36, linewidth=4, edgecolor='darkblue', 
                     facecolor='none', linestyle='-')
ax.add_patch(l1_outer)

# Label L1
ax.text(-0.5, 18, 'L1 Tile\n36 km', ha='right', va='center', 
       fontsize=12, fontweight='bold', color='darkblue')

# Draw L2 grid with alternating colors
colors_2d = [['white', 'lightgray'] * 3] * 3
for i in range(6):
    for j in range(6):
        x, y = i * 6, j * 6
        color = 'white' if (i + j) % 2 == 0 else 'lightgray'
        l2_rect = Rectangle((x, y), 6, 6, linewidth=1.5, edgecolor='darkgreen', 
                           facecolor=color, alpha=0.5)
        ax.add_patch(l2_rect)
        
        # Add L2 tile label
        ax.text(x + 3, y + 3, f'L2\n({i},{j})', ha='center', va='center',
               fontsize=8, color='darkgreen', fontweight='bold')

# Add dimensions
ax.annotate('', xy=(0, -0.5), xytext=(36, -0.5),
           arrowprops=dict(arrowstyle='<->', lw=2, color='darkblue'))
ax.text(18, -0.8, '36 km (36,000 m)', ha='center', fontsize=10, 
       fontweight='bold', color='darkblue')

ax.annotate('', xy=(0, 0), xytext=(6, 0),
           arrowprops=dict(arrowstyle='<->', lw=2, color='darkgreen'))
ax.text(3, -0.3, '6 km', ha='center', fontsize=9, 
       fontweight='bold', color='darkgreen')

# Add grid lines for clarity
for i in range(7):
    ax.axvline(i * 6, color='darkgreen', linewidth=1.5, alpha=0.8)
    ax.axhline(i * 6, color='darkgreen', linewidth=1.5, alpha=0.8)

# Add info box
info_text = '''L1 Tile:
• 36,000 m × 36,000 m
• 600 × 600 pixels
• 60 m per pixel

L2 Tiles (each):
• 6,000 m × 6,000 m  
• 600 × 600 pixels
• 10 m per pixel

Nesting: 6 × 6 = 36 tiles'''

ax.text(37.5, 18, info_text, ha='left', va='center', fontsize=10,
       bbox=dict(boxstyle='round', facecolor='wheat', edgecolor='black', 
                linewidth=2, pad=10),
       family='monospace')

plt.tight_layout()
plt.savefig('/mnt/user-data/outputs/grid_nesting_detail.png', 
           dpi=300, bbox_inches='tight', facecolor='white')
print("Grid nesting detail diagram saved!")

print("\nDiagrams created successfully!")
print("- grid_system_overview.png: Complete system overview")
print("- grid_nesting_detail.png: Detailed view of tile nesting")
