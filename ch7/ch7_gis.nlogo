;; Original code published with:
;; Davies, B., Romanowska, I., Harris, K., Crabtree, S.A., 2019.
;; Combining Geographic Information Systems and Agent-Based Models in Archaeology: Part 2 of 3.
;; Advances in Archaeological Practice 7, 185–193. https://doi.org/10.1017/aap.2019.5

;; Modified and extended by C. Wren

extensions [ gis ]

breed [quarries quarry]
breed [foragers forager]
globals [ elevation-dataset quarries-dataset base orth ]

foragers-own [ toolkit ]
quarries-own [ id name ]
patches-own [ patch-elevation assemblage material-type diversity patch-quarry assemblage-size water-distance]

to setup
  clear-all

  ; use coordinate system associated with raster dataset
  gis:load-coordinate-system "dem.prj"

  ; load elevation data from ascii raster
  set elevation-dataset gis:load-dataset "dem.asc"
  ;  load lithic source data from point shapefile
  set quarries-dataset gis:load-dataset "quarries.shp"
  ; resize the world to fit the patch-elevation data
  gis:set-world-envelope gis:envelope-of elevation-dataset
  ;gis:set-world-envelope gis:envelope-union-of gis:envelope-of elevation-dataset gis:envelope-of quarries-dataset

  ; add elevation data to patch data and color accordingly
  let mx gis:maximum-of elevation-dataset
  ask patches [
    set patch-elevation ( gis:raster-sample elevation-dataset self )
    ifelse patch-elevation > 0  [
      set pcolor scale-color green patch-elevation 0 mx
    ]
    [
      set pcolor blue
    ]
  ]

  ; mark the locations of quarries by finding the intersections between the vectors and patches.
  ; this is problematic in cases where there are two quarries on a patch or if a quarry is on the border of two patches
  ask patches [
    if gis:intersects? quarries-dataset self [
      set patch-quarry true
      set pcolor red
    ]
  ]

  ; this code accesses the exact location of each quarry
  let points gis:feature-list-of quarries-dataset
  foreach points [ quarry-point ->
    let location gis:location-of (first first gis:vertex-lists-of quarry-point)
    let temp_id gis:property-value quarry-point "ID"
    let temp_name gis:property-value quarry-point "Name"
    create-quarries 1 [
      setxy item 0 location item 1 location
      set size 2
      set shape "circle"
      set color red
      set id temp_id
      set name temp_name
    ]
  ]

  ; create an agent with an empty toolkit list
  ask n-of num-foragers patches with [ patch-elevation > 0 ] [
    sprout-foragers 1 [
      set size 8
      set shape "person"
      set color yellow
      set toolkit []
    ]
  ]

  ;give patches empty assemblage lists
  ask patches [
    set assemblage []
  ]
  reset-ticks
end

to go
  ask foragers [
    ; use the chooser in the interface to do random or target walk
    ifelse random-walk? [
      random-walk
    ][
      target-walk
    ]

    ; when the agent comes accross a quarry they should reprovision their toolkit
    if patch-quarry = true [
      reprovision-toolkit
    ]

    ; if any tools in toolkit, discard
    if length toolkit > 0 [
      pass-artefact
      discard-tools
    ]
  ]

  if viz-assemblages? [
    display-assemblages
  ]
  ; at the end of the run colour the map so that we can see where did the agent go and dropped lithics
  if ticks = time-limit [
    display-assemblages
    stop
  ]
  tick
end

to random-walk
  ; random walk, note the agent moves at different distances depending on whether the step was in a cardinal direction or on a diagonal
  move-to one-of neighbors with [ patch-elevation > 0 ]
end

to target-walk
  ; target walk, is only triggered if the agent carries less than 10% of its capacity
  ifelse length toolkit < max-carry * 0.1 [
    let t min-one-of patches with [patch-quarry = true] [distance myself]
    face t
    ifelse [patch-elevation] of patch-ahead 1 > 0 [ ; make sure not to walk into water, this will become problematic for convex shaped landmasses
      move-to patch-ahead 1
    ][
      random-walk ; so if the patch ahead is water, do some more random walk to get unstuck
    ]
  ][
    random-walk ; agent do random walk if their toolkit is not running low
  ]
end

to go-down-hill
  ;  example code to show how the agent mobility can be shaped by topography
  ask foragers [
    let next min-one-of neighbors with [patch-elevation > 0] [patch-elevation]
    move-to next
  ]
end

to walk-quarry
  ; example code to show how the agent can use use target walk to go the most straight way to a target
  ask foragers [
    let nearest-quarry min-one-of patches with [patch-quarry = true] [distance myself]
    face nearest-quarry
    fd 1
  ]
end

to reprovision-toolkit
  ; stores the ID of a nearby quarry as a temporary variable t
  let t gis:property-value first (filter [ q -> gis:contained-by? q patch-here] (gis:feature-list-of quarries-dataset)) "ID"

  ; repeatedly adds value t to toolkit until toolkit is full
  while [ length toolkit < 100 ] [
    set toolkit lput t toolkit
  ]
end

to discard-tools
  ; selects random item from toolkit
  let i random length toolkit

  ; adds that item to the local assemblage
  ask patch-here [
    set assemblage lput (item i [ toolkit ] of myself) assemblage
  ]

  ; removes that item from toolkit
  set toolkit remove-item i toolkit
end

to display-assemblages
  ; end of the run visualisation
  let mx  max [ length assemblage ] of patches ; mx is the max number of lithic pieces dropped anywhere on the map
  ask patches with [ length assemblage > 0 ] [
    	set pcolor scale-color red (length assemblage) 0 mx ; the patch colour is scaled between zero and mx, the darker the more pieces
  	]
end

to write-assemblages
  ; saves the list of lithics to an asc file
  ask patches [set assemblage-size length assemblage]
  let assemblage-dataset gis:patch-dataset assemblage-size
  gis:store-dataset assemblage-dataset "assemblages.asc"
end

to write-diversity
;calculates diversity as the number of unique elements in
;each patch's assemblage list, then exports this as
;an ASCII raster
ask patches [ set diversity length remove-duplicates assemblage ]
  let raster gis:patch-dataset diversity
  gis:store-dataset raster "diversity.asc"
end

to pass-artefact
  ; example code to show how to enable agents to share raw materials among each other
  ask foragers [
    let t min-one-of other foragers in-radius 3 [distance myself]
    let i random length toolkit
    let passed? false

    if t != nobody [
      ask t [
        if length toolkit < max-carry [
          set toolkit lput (item i [ toolkit ] of myself) toolkit
          set passed? true
        ]
      ]
    ]

    if passed? [
      set toolkit remove-item i toolkit
    ]
  ]
end

to calc-water-distance
  ; example code to show how to store information to avoid costly recalculting it at each time step
  ask patches with [patch-elevation > 0] [
    let p min-one-of patches with [patch-elevation <= 0] [distance myself]
    set water-distance distance p
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
862
433
-1
-1
2.0
1
10
1
1
1
0
1
1
1
0
321
0
206
0
0
1
ticks
30.0

BUTTON
5
10
72
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
75
10
138
43
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
5
85
190
118
max-carry
max-carry
0
100
100.0
10
1
NIL
HORIZONTAL

SLIDER
5
120
190
153
time-limit
time-limit
1000
100000
45000.0
1000
1
NIL
HORIZONTAL

BUTTON
75
365
205
398
write diversity
write-diversity
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
5
155
135
188
random-walk?
random-walk?
1
1
-1000

BUTTON
140
10
203
43
step
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
75
400
205
433
write assemblages
write-assemblages
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
5
50
190
83
num-foragers
num-foragers
1
10
1.0
1
1
NIL
HORIZONTAL

BUTTON
5
225
135
258
display-assemblages
display-assemblages
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
5
190
135
223
viz-assemblages?
viz-assemblages?
1
1
-1000

TEXTBOX
10
270
160
311
n.b. leaving the viz-assemblages? switch on will slow your model considerably
11
0.0
1

@#$#@#$#@
## WHAT IS IT?

A model used in Davies et al. (2019) which draws on a neutral model of stone procurement by Brantingham (2003), and builds directly on work developed in Romanowska et al. (2019).

Davies, Benjamin, Iza Romanowska, Kathryn Harris, and Stefani A. Crabtree. 2019. “Combining Geographic Information Systems and Agent-Based Models in Archaeology: Part 2 of 3.” Advances in Archaeological Practice 7 (2): 185–93. https://doi.org/10.1017/aap.2019.5.

Romanowska, Iza, Stefani A. Crabtree, Kathryn Harris, and Benjamin Davies. 2019. “Agent-Based Modeling for Archaeologists: Part 1 of 3.” Advances in Archaeological Practice 7 (2): 178–84. https://doi.org/10.1017/aap.2019.6.

Crabtree, Stefani A., Kathryn Harris, Benjamin Davies, and Iza Romanowska. 2019. “Outreach in Archaeology with Agent-Based Modeling: Part 3 of 3.” Advances in Archaeological Practice 7 (2): 194–202. https://doi.org/10.1017/aap.2019.4.

This version has been modified by Wren for use an example model used in chapter 7 of Romanowska, I., Wren, C., Crabtree, S. 2021. Agent-Based Modeling for Archaeology: Simulating the Complexity of Societies. Santa Fe, NM: SFI Press.

Code blocks: 7.0-7.20

## HOW IT WORKS

During each time step, the turtles move to one of the surrounding patches or stays on their current patch. Use the random-walk? switch to control movement type. 

Turtles possess a *toolkit* which contains stone objects that originate from a particular quarry. After each sequence of movements, if the turtle has any objects in its toolkit, it will discard one object, which becomes part of the *assemblage* of the local patch. 

A set of quarry locations exist in the map. If the turtle crosses over a patch with a quarry, it will replenish its toolkit with stone objects from that quarry up to a preset *max-carry* limit. If num-foragers is greater than one, agents who come within range of another agent will exchange artefacts.  

After a period of time (*time-limit*), the simulation stops, and the patches with stone objects in their assemblages are shaded red according to the number of artefacts.

## HOW TO USE IT

This simulation is used to demonstrate how to import, use, and export GIS data for archaeological applications. In order to use this model, the following list of files need to be included in the same directory as the .nlogo file:
dem.asc
dem.asc.aux.xml
dem.prj
quarries.dbf
quarries.prj
quarries.qpj
quarries.shp
quarries.shx

Press setup and go to run the model. After the run is finished you can export the data by pressing on 
write-diversity  - calculates and saves the number of unique raw materials
write-assembalges  - saves the composition of the patch assemblage


## CREDITS AND REFERENCES

Brantingham, P. J. 2003. “A Neutral Model of Stone Raw Material Procurement.” American Anthropologist 68 (3): 487–509.

Davies et al. (2019) "Combining Geographic Information Systems and Agent-Based Models in Archaeology.  A step-by-step guide for using agent-based modeling in archaeological research (Part II of III)" Advances in Archaeological Practice

Romanowska et al. (2019) "Agent-based Modeling for Archaeologists. A step-by-step guide for using agent-based modeling in archaeological research (Part I of III)" Advances in Archaeological Practice
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
1
@#$#@#$#@
