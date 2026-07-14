ONE-DAY BRAINSTORM IDEA

1. Project overview

A. What kind of racing game are you going to create? Provide the high-level description of the project and outline its major software components.

We are going to create a racing game where teams of two compete against one another.  One person is in charge of driving the vehicle while the other person is in charge of the track. Being in charge of the track involves sabotaging the other teams, changing the track to give their own player an advantage, and seeing future obstacles/parts of the track to warn their players. The driving player can only see a small part of the track at one time.

B. Which specializations does your project cover? (Choices include (i) interactivity; (ii) visual effects; (iii) computer gameplay; and (iv) networking.)

Our project covers interactivity through allowing players to interact with obstacles on the map as well as interact and converse with different players. Our project covers networking through allowing players to connect to a central server through our client side app.

2. Project components

A. Which are the main parts of the project?

The main parts of the project are:
The server side app which includes:
Library for visual elements
Library for collisions and player interactions
Server module for handling player connections and permissions
Modules for cars, obstacles, powerups, and maps
Module for running a game
The client side app which includes:
Library for drawing cars, obstacles, powerups, etc on the screen
Module for interference (track player)
Module(s) for stats or player info (leaderboard, available inventory, etc.)
Module for racing mode (racing player)
A protocol for them (the server and client applications) to communicate with each other
Pipe rpc
Server owns all logic. Pushes on update
Client only updates info on their heading, speed, etc. and is in charge of rendering


B. Which parts of the project can be cut for time/interest if necessary?
We could cut out the number of interference strategies the track player can invoke.



C. Which parts remain out of scope of this project?
We were thinking of future extensions where we race different types of vehicles on different types of tracks like airplanes in the air. 
We were also thinking of adding maybe voice connection between the two players or other communication strategies. 

D. Which parts will have the most technical/software complexity/difficulty? Describe the nature of the challenges.
There will be many challenges with the multiplayer aspect, since all players will be present on the same track, there might be issues with race conditions or fairness.
Generating different views for players depending on if they are track players or racing ones








UI/UX design
Powerups
Powerups
Speed boost
Invincibility, unaffected by individual power downs
Counter strategies
Glider, players can glide over drops in the track
Flame magic to counteract ice
Flash lights for cave sections
Axe for vine sections
Power down
Track powerdowns
Track player can drop away a portion of the track (breaking bridges)
Cars fall into the 
water/void(?) unless their own track player gives their player a glider in time
Some type of slippery thing
Makes track very slippery for all racing players. Melts in X seconds.
Closing castle gates in front of people
Forces them to take a different route
Caves only
Can trigger stalstalactites to fall down.
Individual powerdowns
Vines across the track to make moving through very slow. Goes away in X seconds
Reduces speed by X% for X seconds.
Mud bombs
Blocks visibility for X seconds.

Things we have to think about
Switching roles
Theme
Forest, castle, game of thrones vibe.


State of the game
Tag every update (input and output) with a globally unique player ID
One pipe
Server only 
Should keep track of 
List of all players and their details (names, track or racer, number of laps, etc.)
Where all players are on the map and velocities
State of track powerdowns (ex. If bridge #1 is collapsed or not)
Includes timers on how long the powerdowns last
Track player (client)
Should keep track of
List of all players and their details (names, track or racer, number of laps, etc.)
How much inventory they have
Sends out
Uses of powerup/powerdown
Receives 
Updated effects from use of powerup/powerdown

Driver (client)
Should keep track of 
List of all players and their details (names, track or racer, etc.)
Sends out
Keyboard input (desired heading and velocity)
Receives
Updated coordinates + velocity of client
Includes powerdowns (speed reduction, etc.)
Visual state of the car (exploding, with wings, etc.)



