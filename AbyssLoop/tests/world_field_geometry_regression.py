"""Numerical guard for the projected legacy landscape cells on the new square map."""
from __future__ import annotations
import math
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
TILE = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
CELLS = re.findall(r'"(\d+:\d+)"', TILE.split("const MAX_WORLD_TILES_PER_ROUTE_SECTOR")[0])
SIZES = [(300,350),(620,420),(900,600),(1280,720),(1440,900),(1920,1080)]
SHAPES = {
    "classic_ring": (4,3,11,8),
    "narrow_ring": (5,2,9,10),
    "deep_descent": (4,2,10,9),
    "fractured_loop": (3,4,13,6),
}
MAP_COLS, MAP_ROWS = 19, 14
FIELD_COLS, FIELD_ROWS = 10, 8

def road_cells(shape):
    x,y,w,h=SHAPES[shape]; r=x+w-1; b=y+h-1; out=[]
    for col in range(x,r+1): out.append((col,y))
    for row in range(y+1,b+1): out.append((r,row))
    for col in range(r-1,x-1,-1): out.append((col,b))
    for row in range(b-1,y,-1): out.append((x,row))
    return out

def world_map(road):
    blocked=set(road); used=set(); result={}
    for key in CELLS:
        col,row=map(int,key.split(':'))
        pref=((col+0.5)*MAP_COLS/FIELD_COLS-0.5,(row+0.5)*MAP_ROWS/FIELD_ROWS-0.5)
        best=None; bestcost=math.inf
        for y in range(MAP_ROWS):
            for x in range(MAP_COLS):
                if (x,y) in blocked or (x,y) in used: continue
                cost=(x-pref[0])**2+(y-pref[1])**2+((y*MAP_COLS+x)%7)*0.0001
                if cost<bestcost: bestcost=cost; best=(x,y)
        if best is not None:
            result[key]=best; used.add(best)
    return result

assert "const MAP_COLUMNS := 19" in VIEW and "const MAP_ROWS := 14" in VIEW
assert "const ROAD_CELL_COUNT := 34" in VIEW
checks=0; min_cell_size=math.inf
for width,height in SIZES:
    cell=min((width-28)/MAP_COLS,(height-64)/MAP_ROWS)
    min_cell_size=min(min_cell_size,cell)
    mapw,maph=MAP_COLS*cell,MAP_ROWS*cell
    left,top=(width-mapw)/2,(height-maph)/2
    for shape in SHAPES:
        road=road_cells(shape)
        assert len(road)==34, f"{shape}: expected 34 road squares, got {len(road)}"
        assert len(set(road))==34, f"{shape}: duplicate road squares"
        for i,(x,y) in enumerate(road):
            nx,ny=road[(i+1)%len(road)]
            assert abs(nx-x)+abs(ny-y)==1, f"{shape}: road is not orthogonally connected at {i}"
        mapped=world_map(road)
        assert len(mapped)==len(CELLS), f"{shape} {width}x{height}: not all legacy cells mapped"
        assert len(set(mapped.values()))==len(mapped), f"{shape} {width}x{height}: two persistent cells map to same screen cell"
        assert not (set(mapped.values()) & set(road)), f"{shape} {width}x{height}: landscape target overlaps road"
        for key,(x,y) in mapped.items():
            cx=left+(x+0.5)*cell; cy=top+(y+0.5)*cell
            assert left+cell/2-0.01 <= cx <= left+mapw-cell/2+0.01
            assert top+cell/2-0.01 <= cy <= top+maph-cell/2+0.01
            checks+=1
assert "func _get_map_rect() -> Rect2" in VIEW
assert "func _draw_map_grid(route_geometry: Dictionary)" in VIEW
assert "func _get_world_display_cell_map(road_cells: Array) -> Dictionary" in VIEW
assert "var slot := road_cells.find(coord)" in VIEW
print(f"WORLD FIELD GEOMETRY REGRESSION PASSED: {checks} landscape targets mapped uniquely off the 34-cell road across {len(SIZES)} view sizes and {len(SHAPES)} shapes.")
print(f"Smallest supported square tile: {min_cell_size:.2f}px; physical/runtime rendering still requires Godot verification.")
