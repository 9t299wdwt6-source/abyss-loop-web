"""Offline geometry stress test for square-grid route contours."""
from pathlib import Path
import math
ROOT=Path(__file__).resolve().parents[1]
VIEW=(ROOT/"scripts/ui/route_view.gd").read_text(encoding="utf-8")
SHAPES={"classic_ring":(4,3,11,8),"narrow_ring":(5,2,9,10),"deep_descent":(4,2,10,9),"fractured_loop":(3,4,13,6)}
SIZES=((300,350),(620,420),(900,600),(1280,720),(1440,900),(1920,1080))
COUNTS=(12,14,16,18,20,22,34)
def road_cells(shape):
 x,y,w,h=SHAPES[shape]; r=x+w-1; b=y+h-1; a=[]
 for c in range(x,r+1):a.append((c,y))
 for rr in range(y+1,b+1):a.append((r,rr))
 for c in range(r-1,x-1,-1):a.append((c,b))
 for rr in range(b-1,y,-1):a.append((x,rr))
 return a
def route_points(width,height,shape,count):
 cols,rows=19,14; cell=min((width-28)/cols,(height-64)/rows); left=(width-cols*cell)/2; top=(height-rows*cell)/2; road=road_cells(shape)
 return [(left+(road[round(i*len(road)/count)%len(road)][0]+.5)*cell,top+(road[round(i*len(road)/count)%len(road)][1]+.5)*cell) for i in range(count)],cell
scenarios=0; min_gap=math.inf
for width,height in SIZES:
 for shape in SHAPES:
  road=road_cells(shape); assert len(road)==34 and len(set(road))==34
  for count in COUNTS:
   points,cell=route_points(width,height,shape,count)
   assert len(set(points))==count, f"duplicate logical route nodes {width}x{height} {shape} n={count}"
   marker=max(12,min(34,cell*.74)); hit=max(5,min(18,cell*.38))
   for i,p in enumerate(points):
    q=points[(i+1)%count]; distance=math.dist(p,q); min_gap=min(min_gap,distance-2*hit)
    assert distance>2*hit, f"adjacent clickable route nodes overlap: {width}x{height} {shape} n={count}"
    assert 0<p[0]<width and 0<p[1]<height
   scenarios+=1
assert "const MAP_COLUMNS := 19" in VIEW and "const ROAD_CELL_COUNT := 34" in VIEW
assert "func _get_road_grid_coordinates() -> Array[Vector2i]:" in VIEW
print(f"ROUTE TOPOLOGY STRESS REGRESSION PASSED: {scenarios} square-grid scenarios over {len(SIZES)} viewport sizes, {len(SHAPES)} contours and {len(COUNTS)} node counts.")
print(f"Minimum computed gap between adjacent hit zones: {min_gap:.2f}px; Godot runtime still required for final rendering proof.")
