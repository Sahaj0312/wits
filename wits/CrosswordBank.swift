//
//  CrosswordBank.swift
//  wits
//
//  The crossword's clue bank: wits-original clues over common English words,
//  written for this app (no licensed puzzle data). Each line is
//  ANSWER|tier|clue — tier 1 is everyday, 2 is moderate, 3 is tricky — and
//  the generator draws on it to fill fresh mini grids, so the same answer can
//  reappear but never the same puzzle.
//

import Foundation

nonisolated struct CrosswordEntry: Sendable {
    let answer: String
    let tier: Int
    let clue: String
}

nonisolated enum CrosswordBank {
    /// Entries grouped by answer length, parsed once.
    static let byLength: [Int: [CrosswordEntry]] = {
        var grouped: [Int: [CrosswordEntry]] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count == 3,
                  let tier = Int(parts[1]) else { continue }
            let answer = String(parts[0])
            grouped[answer.count, default: []].append(
                CrosswordEntry(answer: answer, tier: tier, clue: String(parts[2])))
        }
        return grouped
    }()

    // Answers must be unique, uppercase A–Z only.
    static let raw = """
ACE|1|Highest card in the deck
ACT|1|Part of a play
ADD|1|Put numbers together
AGE|1|Number of birthdays you've had
AGO|1|In the past, as "long ___"
AID|1|Help out
AIM|1|Point at a target
AIR|1|What we breathe
ALE|2|Pub pour
ALL|1|Every last one
ANT|1|Picnic-raiding insect
APE|1|Gorilla or chimp
APP|1|Phone download
ARC|2|Part of a circle
ARM|1|Elbow's limb
ART|1|Museum hangings
ASH|2|Campfire leftover
ASK|1|Pose a question
ATE|1|Had dinner
AWE|2|Wide-eyed wonder
BAD|1|Not good
BAG|1|Grocery carrier
BAN|2|Forbid outright
BAR|1|Chocolate unit
BAT|1|Baseball club
BAY|2|Curved coastline
BED|1|Place to sleep
BEE|1|Honey maker
BET|1|Poker wager
BIB|1|Baby's meal protector
BIG|1|Far from small
BIN|1|Recycling container
BIT|1|Small piece
BOA|2|Feathery scarf
BOW|2|Arrow launcher
BOX|1|Cardboard container
BOY|1|Young fellow
BUD|2|Flower-to-be
BUG|1|Creepy-crawly
BUN|1|Burger bread
BUS|1|School transport
BUY|1|Purchase
CAB|1|Taxi
CAN|1|Soup container
CAP|1|Baseball hat
CAR|1|Garage occupant
CAT|1|Purring pet
COB|2|Corn core
COT|2|Fold-up bed
COW|1|Farm moo-er
CRY|1|Shed tears
CUB|1|Bear baby
CUE|2|Actor's signal
CUP|1|Coffee vessel
CUT|1|Snip
DAB|2|Tiny touch of paint
DAD|1|Pop
DAM|2|River blocker
DAY|1|24 hours
DEN|2|Lion's lair
DEW|2|Morning grass droplets
DIG|1|Use a shovel
DIM|2|Barely lit
DIP|1|Chip's partner
DOE|2|Female deer
DOG|1|Loyal barker
DOT|1|Tiny round mark
DRY|1|Not wet
DUE|2|Owed
DUO|2|Pair of performers
EAR|1|Hearing organ
EAT|1|Have a meal
EEL|2|Slippery swimmer
EGG|1|Omelet essential
EGO|2|Sense of self
ELF|1|Santa's helper
ELM|3|Stately shade tree
END|1|Finish line
ERA|2|Stretch of history
EVE|2|Night before a holiday
EYE|1|Seeing organ
FAN|1|Devoted follower
FAR|1|A long way off
FAT|1|Butter is mostly this
FEE|2|Service charge
FEW|1|Not many
FIG|2|Newton fruit
FIN|1|Shark's blade
FIT|1|In good shape
FIX|1|Repair
FLY|1|Buzzing pest
FOE|2|Enemy
FOG|1|Thick morning mist
FOX|1|Sly woodland animal
FUN|1|A good time
GAP|1|Space between
GAS|1|Fuel pump fill
GEL|2|Hair goo
GEM|2|Jeweler's stone
GET|1|Receive
GUM|1|Chewy stick
GUT|2|Belly
GYM|1|Workout spot
HAM|1|Sandwich meat
HAT|1|Head topper
HAY|1|Barn bale
HEN|1|Egg layer
HID|2|Stayed out of sight
HIP|2|Joint below the waist
HIT|1|Chart-topping song
HOP|1|Bunny's move
HOT|1|Like fresh coffee
HUG|1|Warm embrace
HUM|2|Sing with closed lips
HUT|2|Simple shelter
ICE|1|Frozen water
ILL|2|Under the weather
INK|1|Pen filler
ION|3|Charged particle
IVY|2|Wall-climbing vine
JAM|1|Toast topper
JAR|1|Pickle container
JAW|1|Chin's bone
JET|1|Fast plane
JOB|1|Nine-to-five
JOG|1|Slow run
JOY|1|Pure happiness
KEY|1|Lock opener
KID|1|Youngster
LAB|2|Scientist's workplace
LAP|1|Sitting cat's spot
LAW|1|Rule of the land
LEG|1|Knee's limb
LID|1|Jar topper
LIE|2|Falsehood
LIP|1|Kiss planter
LOG|1|Fireplace fuel
LOT|2|Parking area
LOW|1|Opposite of high
MAP|1|Treasure hunter's guide
MAT|1|Yoga accessory
MIX|1|Stir together
MOB|2|Unruly crowd
MOP|1|Floor cleaner
MUD|1|Rainy-day mess
MUG|1|Cocoa cup
NAP|1|Afternoon snooze
NET|1|Goal fabric
NEW|1|Fresh off the shelf
NOD|1|Silent yes
NOW|1|This very moment
NUT|1|Squirrel's stash
OAK|2|Acorn tree
OAR|2|Rowboat paddle
ODD|1|Like 3 or 7
OFF|1|Not on
OIL|1|Olive squeeze
OLD|1|Far from new
ONE|1|Loneliest number
OWE|2|Be in debt
OWL|1|Night hooter
PAD|2|Writer's tablet
PAL|1|Buddy
PAN|1|Frying vessel
PAW|1|Dog's foot
PEA|1|Little green veggie
PEN|1|Ink stick
PET|1|Family animal
PIE|1|Thanksgiving dessert
PIG|1|Farm oinker
PIN|1|Bowling target
PIT|2|Peach center
POD|2|Pea's home
POT|1|Stew vessel
PRO|2|Expert
PUB|2|British watering hole
RAG|2|Cleaning cloth
RAM|2|Male sheep
RAN|1|Sprinted
RAT|1|Sewer rodent
RAW|2|Uncooked
RAY|2|Beam of light
RED|1|Stop-sign color
RIB|2|Cage bone
RIM|2|Basketball hoop's edge
ROW|1|Line of seats
RUG|1|Floor cover
RUN|1|Marathon activity
RYE|3|Deli bread choice
SAD|1|Feeling blue
SAP|3|Maple tree fluid
SAW|1|Carpenter's cutter
SEA|1|Salty expanse
SET|2|Tennis unit
SEW|1|Use a needle and thread
SHY|1|Not outgoing
SIP|1|Small drink
SIT|1|Take a seat
SIX|1|Half a dozen
SKI|1|Slope glider
SKY|1|Where clouds live
SLY|2|Fox-like
SON|1|Parent's boy
SPA|2|Massage destination
SPY|1|Secret agent
SUM|2|Addition result
SUN|1|Center of our solar system
TAB|2|Restaurant bill
TAG|1|Playground chase game
TAN|2|Beach souvenir
TAP|1|Faucet
TAR|3|Road-paving goo
TAX|2|April payment
TEA|1|Kettle brew
TEN|1|Perfect score
TIE|1|Suit accessory
TIN|2|Can metal
TIP|1|Waiter's bonus
TOE|1|Sock filler
TON|2|2,000 pounds
TOP|1|Opposite of bottom
TOW|2|Haul behind
TOY|1|Playroom item
TRY|1|Give it a shot
TUB|1|Bath spot
TUG|2|Sharp pull
TWO|1|Pair count
URN|3|Coffee dispenser at events
USE|1|Put to work
VAN|1|Mover's vehicle
VET|2|Pet doctor
VOW|2|Wedding promise
WAR|2|Peace's opposite
WAX|2|Candle material
WAY|1|Route
WEB|1|Spider's trap
WET|1|Soaked
WIG|1|Fake hair
WIN|1|Take first place
WIT|2|Quick humor
YAK|3|Shaggy Himalayan ox
YES|1|Opposite of no
ZIP|1|Close a jacket
ZOO|1|Lion-viewing spot
ABLE|2|Up to the task
ACHE|1|Dull pain
ACID|2|Vinegar's sharp component
AREA|1|Room's square footage
ALSO|1|In addition
ALTO|3|Choir voice below soprano
AWAY|1|Not home
BABY|1|Newest family member
BACK|1|Spine side
BAKE|1|Make cookies
BALL|1|Round toy
BAND|1|Concert performers
BANK|1|Money keeper
BARN|1|Hay storage building
BASE|2|Bottom layer
BATH|1|Tub soak
BEAN|1|Chili bit
BEAR|1|Honey-loving giant
BEAT|2|Drum rhythm
BELL|1|School ringer
BELT|1|Pants holder
BEND|1|Curve in the road
BEST|1|Number one
BIKE|1|Two-wheeler
BIRD|1|Nest builder
BLUE|1|Clear-sky color
BOAT|1|Lake vessel
BODY|1|What a workout works
BOIL|1|Bubble on the stove
BOLD|2|Fearless
BONE|1|Skeleton piece
BOOK|1|Library loan
BOOT|1|Winter footwear
BORN|1|Brought into the world
BOTH|1|The two together
BOWL|1|Cereal holder
BUSY|1|Swamped
CAGE|1|Bird enclosure
CAKE|1|Birthday dessert
CALM|1|Storm's opposite
CAMP|1|Summer tent trip
CARD|1|Birthday mail
CARE|1|Look after
CART|1|Grocery pusher
CASE|2|Detective's assignment
CASH|1|Paper money
CAST|2|Broken arm's wrapper
CAVE|1|Bat's home
CHEF|1|Restaurant cook
CHIN|1|Face's bottom
CITY|1|Urban area
CLAP|1|Applaud
CLAW|1|Crab pincher
CLAY|2|Potter's material
CLIP|2|Paper fastener
CLUB|2|Members-only group
COAL|2|Stocking lump for the naughty
COAT|1|Winter wear
CODE|2|Programmer's product
COIN|1|Piggy bank drop
COLD|1|Ice cream feel
COMB|1|Hair detangler
COOK|1|Make dinner
COOL|1|Slightly cold
COPY|1|Duplicate
CORD|2|Charger cable
CORE|2|Apple's center
CORN|1|Cob veggie
COST|1|Price tag number
COZY|1|Warm and snug
CREW|2|Ship's team
CROP|2|Farmer's harvest
CUBE|2|Ice shape
CURL|2|Hair loop
DARE|1|Truth's alternative
DARK|1|Needing a flashlight
DART|2|Pub-game missile
DATE|1|Calendar square
DAWN|2|First light
DEAL|1|Bargain
DEEP|1|Like ocean trenches
DEER|1|Antlered forest animal
DESK|1|Homework surface
DIME|2|Ten-cent coin
DISH|1|Dinner plate
DIVE|1|Pool plunge
DOCK|2|Boat parking
DOLL|1|Toy figure
DOOR|1|Knock spot
DOWN|1|Elevator direction
DRAW|1|Sketch
DREW|2|Sketched
DROP|1|Let fall
DRUM|1|Beat keeper
DUCK|1|Pond quacker
DUST|1|Shelf collector
EACH|1|Per item
EARN|1|Work for
EAST|1|Sunrise direction
EASY|1|Simple as pie
ECHO|2|Canyon comeback
EDGE|1|Cliff's rim
EPIC|2|Grand tale
EVEN|2|Like 2, 4, and 6
EXAM|1|Final test
EXIT|1|Way out
FACE|1|Clock front
FACT|1|True statement
FADE|2|Lose color
FALL|1|Leaf-dropping season
FARM|1|Tractor's home
FAST|1|Quick
FEAR|1|Scary movie feeling
FEED|1|Give dinner to
FEET|1|Shoe fillers
FILM|1|Movie
FIND|1|Locate
FINE|1|Perfectly okay
FIRE|1|Campground glow
FISH|1|Aquarium swimmer
FIST|2|Closed hand
FIVE|1|Fingers on a hand
FLAG|1|Pole flyer
FLAT|2|Pancake-like
FLEW|2|Traveled by wing
FLIP|1|Pancake move
FLOW|2|River's movement
FOAM|2|Latte topping
FOLD|1|Laundry chore
FOOD|1|Menu offerings
FOOT|1|Twelve inches
FORK|1|Salad stabber
FORT|2|Pillow construction
FOUR|1|Table-leg count
FREE|1|Costing nothing
FROG|1|Lily pad sitter
FUEL|2|Tank filler
FULL|1|No room left
GAME|1|Night of Monopoly, e.g.
GATE|1|Airport departure spot
GAVE|1|Handed over
GEAR|2|Bike shifter's pick
GIFT|1|Wrapped surprise
GIRL|1|Young lady
GLAD|1|Pleased
GLOW|2|Firefly's light
GLUE|1|Craft stickum
GOAL|1|Soccer score
GOAT|1|Bearded farm climber
GOLD|1|First-place metal
GOLF|1|Eighteen-hole game
GONE|1|Vanished
GOOD|1|Well done
GOWN|2|Ball attire
GRAB|1|Snatch
GRAY|2|Rainy-sky shade
GREW|2|Got taller
GRIN|1|Big smile
GRIP|2|Firm hold
GROW|1|Get bigger
HAIR|1|Barber's medium
HALF|1|Fifty percent
HALL|1|School corridor
HAND|1|Five-finger unit
HANG|1|Put up, as a picture
HARD|1|Tough
HARM|2|Damage
HAWK|2|Keen-eyed hunter bird
HEAD|1|Hat's spot
HEAL|2|Get better
HEAR|1|Use your ears
HEAT|1|Oven output
HELD|2|Kept in hand
HERO|1|Cape wearer
HIDE|1|Seek's partner
HIGH|1|Skyscraper-like
HIKE|1|Trail walk
HILL|1|Small mountain
HINT|1|Helpful nudge
HIVE|2|Bee headquarters
HOLD|1|Keep in your hands
HOLE|1|Donut's center
HOME|1|Where the heart is
HOOK|2|Fishing line's end
HOPE|1|Optimist's feeling
HORN|1|Traffic honker
HOSE|1|Garden waterer
HOUR|1|Sixty minutes
HUGE|1|Elephant-sized
HUNT|2|Search for game
HURT|1|In pain
ICON|2|Desktop clickable
IDEA|1|Light-bulb moment
INCH|1|Ruler unit
INTO|1|Really enjoying
IRON|1|Wrinkle remover
ITEM|2|List entry
JOKE|1|Comedian's line
JUMP|1|Leap
JURY|2|Courtroom twelve
JUST|1|Only
KEEP|1|Hold onto
KIND|1|Nice
KING|1|Chess target
KITE|1|Windy-day flyer
KNEE|1|Leg's hinge
KNEW|2|Was sure of
KNOT|2|Shoelace tangle
LAKE|1|Freshwater expanse
LAMP|1|Bedside light
LAND|1|Plane's goal
LANE|1|Bowling strip
LAST|1|Final
LATE|1|After the bell
LAWN|1|Mowing target
LAZY|1|Couch-bound
LEAF|1|Autumn faller
LEAN|2|Tilt
LEAP|1|Big jump
LEFT|1|Port side
LEND|2|Let borrow
LESS|1|Not as much
LIFE|1|Biography subject
LIFT|1|Pick up
LIME|2|Green citrus
LINE|1|Thing to wait in
LION|1|Mane attraction
LIST|1|Grocery reminder
LIVE|1|Not recorded
LOAF|2|Bread unit
LOCK|1|Key's partner
LONG|1|Far from short
LOOK|1|Take a peek
LOOP|2|Circular path
LOST|1|Needing directions
LOUD|1|Turned way up
LOVE|1|Valentine feeling
LUCK|1|Four-leaf clover gift
LUNG|2|Breathing organ
MAIL|1|Letter delivery
MAIN|2|Most important
MAKE|1|Create
MANY|1|A whole bunch
MASK|1|Halloween face
MATH|1|Class with fractions
MAZE|1|Cornfield puzzle
MEAL|1|Breakfast, lunch, or dinner
MEAT|1|Butcher's stock
MELT|1|What ice does in the sun
MENU|1|Diner's reading
MESS|1|Toddler's aftermath
MILD|2|Salsa for beginners
MILE|1|5,280 feet
MILK|1|Cereal partner
MIND|1|Meditation focus
MINE|2|Gold digger's tunnel
MINT|2|Breath freshener
MIST|2|Light fog
MOOD|1|Emotional weather
MOON|1|Night-sky glow
MORE|1|Oliver's request
MOSS|2|Soft green ground cover
MOST|1|The majority
MOTH|2|Porch-light circler
MOVE|1|Chess turn
MUCH|1|A great deal
NAME|1|What's on a name tag
NAVY|2|Deep blue
NEAR|1|Close by
NECK|1|Giraffe's long feature
NEED|1|Must-have
NEST|1|Egg cradle
NEWS|1|Nightly broadcast
NEXT|1|Right after this
NICE|1|Pleasant
NINE|1|Baseball team count
NOON|1|Midday
NOSE|1|Smell organ
NOTE|1|Fridge reminder
OBOE|3|Double-reed instrument
ODOR|2|Nose news
ONCE|1|A single time
ONLY|1|Just one
OPEN|1|Shop-sign flip
OVAL|2|Egg shape
OVEN|1|Baker's box
OVER|1|Finished
PACE|2|Walking speed
PACK|1|Fill a suitcase
PAGE|1|Book unit
PAID|1|Settled the bill
PAIL|2|Beach bucket
PAIN|1|Ouch cause
PAIR|1|Sock set
PALM|2|Hand's flat side
PARK|1|Picnic place
PART|1|Piece
PASS|1|Hand over
PAST|1|History
PATH|1|Garden walkway
PAVE|3|Lay asphalt
PEAK|2|Mountain top
PEAR|1|Bell-shaped fruit
PEEL|1|Banana skin
PILE|1|Laundry mountain
PINE|2|Evergreen with needles
PINK|1|Flamingo color
PIPE|2|Plumber's tube
PLAN|1|Blueprint
PLAY|1|Recess activity
PLOT|2|Story's backbone
PLUG|2|Outlet filler
PLUS|1|Addition sign
POEM|1|Rhyming lines
POLE|2|North or South point
POND|1|Duck's puddle
POOL|1|Backyard swim spot
POUR|1|Fill a glass
PULL|1|Push's opposite
PUMP|2|Tire filler
PURE|2|Unmixed
PUSH|1|Door instruction
QUIZ|1|Pop test
RACE|1|Track event
RAIN|1|Umbrella weather
RAKE|1|Leaf gatherer
RARE|2|Hard to find
READ|1|Enjoy a book
REAL|1|Not fake
RENT|1|Monthly payment
REST|1|Take a break
RICE|1|Sushi grain
RICH|1|Rolling in money
RIDE|1|Carousel turn
RING|1|Proposal jewelry
RIPE|1|Ready to eat
RISE|1|Get up
ROAD|1|Car's path
ROCK|1|Climber's wall
ROLE|2|Actor's part
ROLL|1|Drum sound
ROOF|1|House topper
ROOM|1|House division
ROOT|1|Tree anchor
ROPE|1|Tug-of-war need
ROSE|1|Valentine flower
RUIN|2|Spoil
RULE|1|Classroom guideline
RUSH|1|Hurry
RUST|2|Old bike's coating
SAFE|1|Out of danger
SAID|1|Spoke
SAIL|1|Boat's sheet
SALT|1|Pepper's partner
SAME|1|Identical
SAND|1|Beach ground
SANG|1|Performed a tune
SAVE|1|Put money aside
SEAL|2|Envelope closer
SEAT|1|Place to sit
SEED|1|Garden starter
SEEK|2|Hide and ___
SEEN|1|Spotted
SELF|2|You, to you
SELL|1|Put on the market
SEND|1|Mail off
SHIP|1|Ocean liner
SHOE|1|Lace-up wear
SHOP|1|Browse the aisles
SHOW|1|TV program
SHUT|1|Close
SICK|1|Home from school
SIDE|1|Fries, e.g.
SIGN|1|Stop ___
SILK|2|Smooth fabric
SING|1|Use your voice
SINK|1|Kitchen basin
SIZE|1|Small, medium, or large
SKIN|1|Body's cover
SLED|1|Snow-day ride
SLIM|2|Narrow
SLOW|1|Snail-paced
SNAP|1|Finger click
SNOW|1|Winter blanket
SOAP|1|Shower bar
SOCK|1|Shoe liner
SODA|1|Fizzy drink
SOFA|1|Living-room seat
SOFT|1|Pillow-like
SOIL|1|Garden dirt
SOLD|1|Auctioneer's cry
SOLO|2|One-person performance
SONG|1|Playlist unit
SOON|1|Before long
SORT|1|Organize
SOUP|1|Spoon meal
SOUR|1|Lemon-like
SPIN|1|Turn around
SPOT|1|Dalmatian mark
STAR|1|Night-sky twinkler
STAY|1|Dog command
STEM|2|Flower's stalk
STEP|1|Stair unit
STIR|1|Mix with a spoon
STOP|1|Red-light order
SUIT|1|Interview attire
SURE|1|Certain
SWIM|1|Pool activity
TAIL|1|Dog's wagger
TAKE|1|Grab
TALE|1|Story
TALK|1|Chat
TALL|1|Basketball-player-like
TAME|2|Far from wild
TANK|2|Fish home
TAPE|1|Gift-wrap need
TASK|1|To-do item
TEAM|1|Group of players
TEAR|2|Rip
TELL|1|Spill the beans
TENT|1|Camper's shelter
TEST|1|Pop quiz's big brother
THAW|2|Defrost
THIN|1|Paper-like
TIDE|2|Ocean's rise and fall
TIDY|1|Neat
TIME|1|What clocks keep
TINY|1|Ant-sized
TIRE|1|Car's rubber ring
TOAD|2|Warty hopper
TOLD|1|Let know
TONE|2|Voice quality
TOOK|1|Grabbed
TOOL|1|Hammer or saw
TORE|2|Ripped
TOSS|1|Gentle throw
TOUR|1|Museum walk-through
TOWN|1|Small city
TRAP|1|Mouse catcher
TRAY|1|Cafeteria carrier
TREE|1|Trunk owner
TRIM|2|Give a light haircut
TRIP|1|Vacation
TRUE|1|Not false
TUBE|2|Toothpaste holder
TUNE|1|Melody
TURN|1|Steering move
TWIN|1|Identical sibling
UGLY|1|Far from pretty
UNIT|2|Apartment, e.g.
UPON|2|Once ___ a time
USED|1|Secondhand
VASE|1|Flower holder
VERY|1|Extremely
VEST|2|Sleeveless layer
VIEW|1|Window scenery
VINE|2|Grape's grower
VOTE|1|Ballot action
WAIT|1|Stand by
WAKE|1|Stop sleeping
WALK|1|Stroll
WALL|1|Picture hanger's spot
WANT|1|Wish for
WARM|1|Toasty
WASH|1|Clean up
WAVE|1|Beach roller
WEAR|1|Have on
WEEK|1|Seven days
WELL|1|Wishing spot
WENT|1|Departed
WEST|1|Sunset direction
WHAT|1|Question starter
WIDE|1|Broad
WILD|1|Untamed
WIND|1|Kite's engine
WING|1|Bird's flier
WIRE|2|Electrician's line
WISE|1|Owl-like
WISH|1|Birthday-candle thought
WOKE|2|Got up
WOLF|1|Howling pack animal
WOOD|1|Lumber
WOOL|1|Sweater fiber
WORD|1|Dictionary entry
WORE|2|Had on
WORK|1|Office activity
WORM|1|Early bird's catch
WRAP|1|Prepare a gift
YARD|1|Lawn's location
YARN|2|Knitter's supply
YEAR|1|365 days
YOGA|1|Mat exercise
ZERO|1|Nothing at all
ZONE|2|Designated area
ABOUT|1|Roughly
ABOVE|1|Overhead
ACTOR|1|Movie star
ADULT|1|Grown-up
AGENT|2|Spy, e.g.
AGREE|1|See eye to eye
AHEAD|1|In front
ALARM|1|Morning buzzer
ALBUM|1|Photo book
ALERT|2|Wide awake
ALIKE|2|Similar
ALIVE|1|Breathing
ALLEY|2|Narrow back street
ALONE|1|Solo
ALOUD|2|For all to hear
AMONG|2|In the middle of
ANGEL|1|Halo wearer
ANGLE|2|Geometry measure
ANGRY|1|Steaming mad
ANKLE|1|Foot's joint
APART|2|Separated
APPLE|1|Teacher's gift
APRON|1|Cook's cover
ARENA|2|Concert venue
AROMA|2|Bakery smell
ARROW|1|Bow's partner
ASIDE|2|Stage whisper
ATLAS|2|Book of maps
AUDIO|2|Sound portion
AVOID|1|Steer clear of
AWAKE|1|Not sleeping
AWARD|1|Trophy
BACON|1|Breakfast strip
BADGE|1|Officer's ID
BAKER|1|Bread maker
BASIC|1|No-frills
BASIL|2|Pesto herb
BEACH|1|Sandcastle site
BEARD|1|Chin cover
BEGAN|1|Started
BEGIN|1|Start
BEING|2|Existence
BELOW|1|Underneath
BENCH|1|Park seat
BERRY|1|Smoothie bit
BIRTH|1|Day one
BLACK|1|Darkest shade
BLADE|2|Knife's edge
BLAME|1|Point fingers at
BLANK|1|Empty space
BLAST|2|Explosion
BLAZE|2|Roaring fire
BLEND|2|Smoothie-maker's verb
BLOCK|1|City square
BLOOM|2|Open, as a flower
BOARD|1|Chess surface
BONUS|1|Extra pay
BOOST|2|Lift up
BOOTH|2|Diner seating
BRAIN|1|Thinking organ
BRAVE|1|Fearless
BREAD|1|Sandwich base
BREAK|1|Recess
BRICK|1|Wall block
BRIDE|1|Aisle walker
BRIEF|2|Short and sweet
BRING|1|Carry along
BROOM|1|Sweeper
BROWN|1|Chocolate shade
BRUSH|1|Painter's tool
BUILD|1|Construct
BUNCH|1|Banana group
BURST|2|Pop
CABIN|1|Woodsy getaway
CABLE|2|TV hookup
CANDY|1|Halloween haul
CANOE|2|Paddler's boat
CARGO|2|Ship's load
CARRY|1|Tote
CATCH|1|Fly-ball feat
CAUSE|2|Reason why
CHAIN|1|Bike part
CHAIR|1|Table partner
CHALK|1|Sidewalk-art stick
CHARM|2|Bracelet dangler
CHART|2|Data picture
CHASE|1|Run after
CHEAP|1|Easy on the wallet
CHECK|1|Restaurant request
CHEEK|1|Blush spot
CHESS|1|Game of kings
CHEST|1|Treasure box
CHIEF|2|Top boss
CHILD|1|Kid
CHILL|1|Relax
CHIME|2|Doorbell sound
CHOIR|2|Singing group
CHORE|1|Household task
CLAIM|2|Say it's yours
CLASS|1|School period
CLEAN|1|Spotless
CLEAR|1|Cloudless
CLIMB|1|Scale
CLOCK|1|Time teller
CLOSE|1|Nearby
CLOTH|1|Fabric
CLOUD|1|Sky fluff
COACH|1|Team leader
COAST|1|Shoreline
COCOA|1|Winter warmer
COLOR|1|Crayon choice
COMET|2|Tailed sky streaker
COMIC|2|Funny-pages feature
CORAL|2|Reef builder
COUCH|1|TV-watching seat
COUNT|1|Say numbers in order
COURT|1|Tennis venue
COVER|1|Book's front
CRAFT|1|Glue-and-glitter project
CRANE|2|Construction lifter
CRASH|1|Cymbal sound
CRAWL|1|Baby's travel
CRAZY|1|Wild
CREAM|1|Coffee lightener
CRISP|2|Like fresh lettuce
CROSS|1|Go over
CROWD|1|Packed-stadium sight
CROWN|1|Royal headwear
CRUMB|2|Cookie leftover
CURVE|2|Road bend
CYCLE|2|Repeating loop
DAILY|1|Every 24 hours
DAIRY|1|Milk section
DANCE|1|Prom activity
DELAY|2|Flight-board bad news
DEPTH|2|How deep it goes
DIARY|1|Private journal
DIRTY|1|Needing a wash
DITCH|2|Roadside trench
DOUGH|1|Cookie starter
DOZEN|1|Twelve
DRAFT|2|Cold-window breeze
DRAIN|1|Sink exit
DRAMA|1|Theater genre
DREAM|1|Sleep story
DRESS|1|Closet hanger-filler
DRIED|2|Like raisins
DRIFT|2|Float along
DRILL|1|Fire ___
DRINK|1|Beverage
DRIVE|1|Take the wheel
DROVE|2|Took the wheel
DRYER|1|Laundry machine
EAGER|1|Raring to go
EAGLE|1|Bald bird
EARLY|1|Before the bell
EARTH|1|Third rock from the sun
EIGHT|1|Octopus's arm count
ELBOW|1|Arm's hinge
EMPTY|1|Like a drained glass
ENEMY|1|Foe
ENJOY|1|Take pleasure in
ENTER|1|Come in
EQUAL|2|The same as
ERROR|1|Mistake
EVENT|1|Calendar entry
EVERY|1|Each and all
EXACT|2|Precise
EXTRA|1|More than needed
FABLE|2|Story with a moral
FAINT|2|Barely visible
FAIRY|1|Tooth ___
FALSE|1|True's opposite
FANCY|1|Dressed up
FAULT|2|Blame
FAVOR|1|Kind deed
FEAST|1|Holiday spread
FENCE|1|Yard border
FEVER|1|Thermometer's finding
FIELD|1|Farm expanse
FIFTY|1|Half of 100
FIGHT|1|Boxing match
FINAL|1|Season-ending game
FIRST|1|Gold-medal place
FLAME|1|Candle top
FLASH|1|Camera burst
FLEET|3|Group of ships
FLOAT|1|Parade entry
FLOCK|2|Sheep group
FLOOD|1|Overflowing river's result
FLOOR|1|What's underfoot
FLOUR|1|Baker's powder
FLUTE|2|Silvery woodwind
FOCUS|1|Camera adjustment
FORCE|2|Push or pull
FORTY|1|Four tens
FOUND|1|No longer lost
FRAME|1|Picture border
FRESH|1|Just baked
FRIED|1|Like diner chicken
FRONT|1|Back's opposite
FROST|2|Windshield coating
FROZE|2|Turned to ice
FRUIT|1|Smoothie base
FUNNY|1|Laugh-worthy
GHOST|1|Sheet-wearing spook
GIANT|1|Beanstalk dweller
GLASS|1|Windowpane material
GLOBE|1|Desktop Earth
GLOVE|1|Winter hand-warmer
GRACE|2|Elegant ease
GRADE|1|Report-card mark
GRAIN|2|Wheat bit
GRAND|2|Piano size
GRAPE|1|Vine fruit
GRASS|1|Lawn green
GREAT|1|Wonderful
GREEN|1|Go-light color
GREET|1|Say hello to
GRILL|1|Backyard cooker
GROUP|1|Bunch
GUARD|1|Museum watcher
GUESS|1|Take a stab
GUEST|1|Party invitee
GUIDE|1|Tour leader
HABIT|2|Hard-to-break routine
HAPPY|1|Smiley
HEART|1|Valentine shape
HEAVY|1|Hard to lift
HELLO|1|Friendly greeting
HONEY|1|Bee product
HORSE|1|Stable resident
HOTEL|1|Traveler's stay
HOUSE|1|Home
HUMAN|1|Person
HUMOR|2|Comedy's essence
HURRY|1|Move it
IDEAL|2|Picture-perfect
IMAGE|2|Picture
INDEX|3|Back-of-book list
INNER|2|Inside
IRONY|3|Fire station burning down, e.g.
ISSUE|2|Magazine edition
JEANS|1|Denim pants
JUDGE|1|Gavel wielder
JUICE|1|Breakfast squeeze
KNEEL|2|Get down on one knee
KNIFE|1|Butter spreader
KNOCK|1|Door tap
LABEL|1|Jar sticker
LARGE|1|Big
LASER|2|Light-show beam
LATER|1|Not now
LAUGH|1|Comedy-club response
LAYER|1|Cake level
LEARN|1|Pick up in school
LEAST|2|Smallest amount
LEAVE|1|Head out
LEMON|1|Sour yellow fruit
LEVEL|1|Video-game stage
LIGHT|1|Lamp output
LIMIT|2|Speed ___
LOCAL|1|Neighborhood-based
LOGIC|2|Puzzle solver's tool
LOOSE|1|Not tight
LOWER|1|Bring down
LOYAL|1|Dog-like
LUCKY|1|Charmed
LUNCH|1|Noon meal
MAGIC|1|Wand work
MAJOR|2|College focus
MANGO|1|Tropical fruit
MAPLE|1|Syrup tree
MARCH|1|Parade walk
MATCH|1|Fire starter
MAYBE|1|Possibly
MAYOR|1|City leader
MEDAL|1|Olympic prize
MELON|1|Cantaloupe, e.g.
MERGE|2|Highway maneuver
MERRY|1|___ Christmas
METAL|1|Iron or gold
MIGHT|2|Strength
MINOR|2|Small-scale
MINUS|1|Subtraction sign
MODEL|1|Runway walker
MONEY|1|Wallet contents
MONTH|1|May or June
MORAL|2|Fable's lesson
MOTOR|1|Engine
MOUNT|2|Climb onto
MOUSE|1|Cheese lover
MOUTH|1|Where teeth live
MOVIE|1|Popcorn's excuse
MUSIC|1|Radio play
NERVE|2|Courage
NEVER|1|Not once
NIGHT|1|Owl's shift
NOBLE|2|Knight-worthy
NOISE|1|Racket
NORTH|1|Compass top
NOVEL|1|Long fiction
NURSE|1|Hospital helper
OCEAN|1|Whale's home
OFFER|1|Put on the table
OFTEN|1|Many times
OLIVE|2|Martini garnish
ONION|1|Tear-jerking veggie
ORBIT|2|Planet's path
ORDER|1|Waiter's request
OTHER|1|Different one
OUGHT|3|Should
OUNCE|2|Small weight unit
OUTER|2|___ space
OWNER|1|Deed holder
PAINT|1|Roller's coat
PANDA|1|Bamboo eater
PANEL|2|Expert group
PAPER|1|Printer load
PARTY|1|Balloon occasion
PASTA|1|Noodle dish
PATCH|2|Jeans repair
PAUSE|1|Remote button
PEACE|1|Dove's symbol
PEACH|1|Fuzzy fruit
PEARL|2|Oyster's gem
PEDAL|1|Bike pusher
PENNY|1|One-cent coin
PHONE|1|Pocket ringer
PHOTO|1|Album filler
PIANO|1|88-key instrument
PIECE|1|Puzzle unit
PILOT|1|Cockpit worker
PITCH|2|Baseball throw
PIZZA|1|Slice source
PLACE|1|Location
PLAIN|2|No toppings
PLANE|1|Airport flyer
PLANT|1|Windowsill green
PLATE|1|Dinner disc
PLAZA|2|Town square
POINT|1|Arrow's tip
POLAR|2|___ bear
PORCH|1|Front-door platform
POWER|1|Outlet output
PRESS|2|Push down
PRICE|1|Tag number
PRIDE|2|Lion group
PRINT|1|Put on paper
PRIZE|1|Contest reward
PROOF|2|Evidence
PROUD|1|Chest-out feeling
PUPIL|2|Eye's center
PUPPY|1|Young dog
QUEEN|1|Chess's most powerful piece
QUICK|1|Speedy
QUIET|1|Library rule
QUILT|2|Patchwork blanket
RADIO|1|Dashboard staple
RAISE|1|Salary bump
RANCH|2|Cattle spread
RANGE|2|Mountain chain
RAPID|2|Very fast
REACH|1|Stretch for
REACT|2|Respond
READY|1|All set
RIVER|1|Bridge crosser
ROAST|1|Sunday dinner
ROBIN|1|Red-breasted bird
ROBOT|1|Sci-fi helper
ROCKY|2|Full of stones
ROUND|1|Circle-shaped
ROUTE|1|Delivery path
ROYAL|1|Palace resident
RULER|1|Straight-line helper
SADLY|2|Unfortunately
SALAD|1|Bowl of greens
SAUCE|1|Pasta topper
SCALE|1|Bathroom weigher
SCARE|1|Spook
SCENE|2|Movie segment
SCENT|2|Perfume's essence
SCOOP|1|Ice-cream serving
SCORE|1|Game total
SCOUT|2|Cookie seller, maybe
SEVEN|1|Lucky number
SHADE|1|Tree's gift on a hot day
SHAKE|1|Jiggle
SHAPE|1|Circle or square
SHARE|1|Split with a friend
SHARK|1|Fin flasher
SHARP|1|Needle-like
SHEEP|1|Wool source
SHELF|1|Book perch
SHELL|1|Beach pickup
SHINE|1|Glow
SHIRT|1|Torso wear
SHORE|1|Beachfront
SHORT|1|Not tall
SHOUT|1|Yell
SHOWN|2|Put on display
SIGHT|1|One of five senses
SILLY|1|Goofy
SINCE|2|From then on
SIREN|2|Ambulance wailer
SIXTY|1|Minutes in an hour
SKATE|1|Rink glider
SKILL|1|Practiced ability
SLEEP|1|Nightly recharge
SLICE|1|Pizza portion
SLIDE|1|Playground chute
SMALL|1|Tiny
SMART|1|Quick-witted
SMELL|1|Nose's job
SMILE|1|Camera request
SMOKE|1|Campfire cloud
SNACK|1|Between-meals bite
SNAKE|1|Legless slitherer
SOLAR|2|Sun-powered
SOLID|2|Not liquid
SORRY|1|Apology word
SOUND|1|Ear input
SOUTH|1|Compass bottom
SPACE|1|Astronaut's workplace
SPARE|2|Trunk tire
SPARK|2|Tiny fire starter
SPEAK|1|Say words
SPEED|1|Racer's obsession
SPELL|1|Bee challenge
SPEND|1|Use money
SPICE|1|Cinnamon, e.g.
SPILL|1|Milk mishap
SPLIT|2|Banana dessert
SPOON|1|Cereal tool
SPORT|1|Soccer or tennis
STAGE|1|Actor's platform
STAIR|1|Step of a flight
STAMP|1|Envelope corner
STAND|1|Get up
START|1|Begin
STATE|1|Texas or Ohio
STEAM|1|Kettle cloud
STEEL|2|Skyscraper metal
STICK|1|Fetch toy
STILL|1|Motionless
STING|1|Bee's defense
STONE|1|Skipping rock
STOOD|2|Was upright
STORE|1|Shopping stop
STORM|1|Thunder bringer
STORY|1|Bedtime request
STOVE|1|Kitchen cooker
STRAW|1|Juice-box tube
STYLE|1|Fashion sense
SUGAR|1|Sweet sprinkle
SUNNY|1|Cloudless
SUPER|1|Better than great
SWEEP|1|Broom's job
SWEET|1|Like candy
SWING|1|Playground seat
TABLE|1|Dinner surface
TASTE|1|Tongue's talent
TEACH|1|Lead a class
TEETH|1|Dentist's focus
THANK|1|Show gratitude
THEME|2|Party's motif
THICK|1|Like pea soup
THING|1|Whatchamacallit
THINK|1|Use your head
THIRD|1|Bronze-medal place
THREE|1|Triangle's side count
THREW|2|Tossed
THUMB|1|Hitchhiker's digit
TIGER|1|Striped big cat
TIGHT|1|Snug
TIMER|1|Kitchen countdown
TITLE|1|Book's name
TODAY|1|This very day
TOKEN|2|Arcade coin
TOOTH|1|Fairy's collectible
TOPIC|1|Discussion subject
TORCH|2|Olympic flame carrier
TOTAL|1|Sum
TOUCH|1|Feel
TOUGH|1|Hard to chew
TOWEL|1|Post-shower wrap
TOWER|1|Castle feature
TRACK|1|Runner's oval
TRADE|1|Swap
TRAIL|1|Hiker's path
TRAIN|1|Track rider
TREAT|1|Trick's partner
TRIAL|2|Courtroom event
TRICK|1|Magician's move
TRUCK|1|Big rig
TRUNK|1|Elephant's nose
TRUST|1|Faith in someone
TRUTH|1|Whole ___ and nothing but
TULIP|2|Spring bulb bloom
TWICE|1|Two times
TWIST|1|Pretzel shape
UNCLE|1|Aunt's husband
UNDER|1|Below
UNION|3|Workers' group
UNITE|2|Join together
UNTIL|1|Up to when
UPPER|2|Higher of two
UPSET|1|Bothered
URBAN|2|City-like
USUAL|2|The regular
VALUE|2|Worth
VIDEO|1|Streaming upload
VIRUS|2|Cold cause
VISIT|1|Drop by
VOICE|1|Singer's instrument
WAGON|1|Little red puller
WASTE|2|Squander
WATCH|1|Wrist clock
WATER|1|What H2O is
WHALE|1|Ocean giant
WHEAT|1|Bread grain
WHEEL|1|Car corner
WHILE|1|During
WHITE|1|Snow shade
WHOLE|1|Complete
WIDTH|2|Side-to-side measure
WINDY|1|Kite-flying weather
WOMAN|1|Lady
WORLD|1|Globe subject
WORRY|1|Fret
WORST|1|Bottom of the barrel
WORTH|2|Value
WRIST|1|Watch spot
WRITE|1|Put pen to paper
WRONG|1|Incorrect
YIELD|2|Triangular road sign
YOUNG|1|Not old
YOUTH|2|The young years
ANTS|1|Picnic-raiding insects
APES|1|Gorillas and chimps
APPS|1|Phone downloads
ARMS|1|Elbows' limbs
BAGS|1|Grocery carriers
BARS|1|Chocolate units
BATS|1|Baseball clubs
BEDS|1|Places to sleep
BEES|1|Honey makers
BETS|1|Poker wagers
BINS|1|Recycling containers
BOWS|2|Arrow launchers
BOYS|1|Young fellows
BUDS|2|Flowers-to-be
BUGS|1|Creepy-crawlies
BUNS|1|Burger breads
CABS|1|Taxis
CANS|1|Soup containers
CAPS|1|Baseball hats
CARS|1|Garage occupants
CATS|1|Purring pets
COTS|2|Fold-up beds
COWS|1|Farm moo-ers
CUBS|1|Bear babies
CUES|2|Actors' signals
CUPS|1|Coffee vessels
DADS|1|Pops
DAYS|1|Calendar units
DENS|2|Lions' lairs
DOGS|1|Loyal barkers
DOTS|1|Tiny round marks
EARS|1|Hearing organs
EGGS|1|Omelet essentials
ENDS|1|Finish lines
ERAS|2|Stretches of history
EYES|1|Seeing organs
FANS|1|Devoted followers
FEES|2|Service charges
FIGS|2|Newton fruits
FINS|1|Sharks' blades
GAPS|1|Spaces between
GEMS|2|Jewelers' stones
GYMS|1|Workout spots
HAMS|1|Sandwich meats
HATS|1|Head toppers
HENS|1|Egg layers
HITS|1|Chart-topping songs
HUGS|1|Warm embraces
HUTS|2|Simple shelters
JAMS|1|Toast toppers
JARS|1|Pickle containers
JAWS|1|Chins' bones
JETS|1|Fast planes
JOBS|1|Nine-to-fives
KEYS|1|Lock openers
KIDS|1|Youngsters
LABS|2|Scientists' workplaces
LAPS|1|Pool lengths
LAWS|1|Rules of the land
LEGS|1|Knees' limbs
LIDS|1|Jar toppers
LIPS|1|Kiss planters
LOGS|1|Fireplace fuel pieces
MAPS|1|Treasure hunters' guides
MATS|1|Yoga accessories
MOPS|1|Floor cleaners
MUGS|1|Cocoa cups
NAPS|1|Afternoon snoozes
NETS|1|Goal fabrics
NUTS|1|Squirrels' stash
OAKS|2|Acorn trees
OARS|2|Rowboat paddles
OWLS|1|Night hooters
PADS|2|Writers' tablets
PALS|1|Buddies
PANS|1|Frying vessels
PAWS|1|Dogs' feet
PEAS|1|Little green veggies
PENS|1|Ink sticks
PETS|1|Family animals
PIES|1|Thanksgiving desserts
PIGS|1|Farm oinkers
PINS|1|Bowling targets
PITS|2|Peach centers
PODS|2|Peas' homes
POTS|1|Stew vessels
PROS|2|Experts
PUBS|2|British watering holes
RAGS|2|Cleaning cloths
RAMS|2|Male sheep
RATS|1|Sewer rodents
RAYS|2|Beams of light
RIBS|2|Cage bones
RIMS|2|Hoops' edges
ROWS|1|Lines of seats
RUGS|1|Floor covers
SAWS|1|Carpenters' cutters
SEAS|1|Salty expanses
SIPS|1|Small drinks
SKIS|1|Slope gliders
SONS|1|Parents' boys
SPAS|2|Massage destinations
TABS|2|Restaurant bills
TAGS|1|Price stickers
TAPS|1|Faucets
TIES|1|Suit accessories
TINS|2|Small metal boxes
TIPS|1|Waiters' bonuses
TOES|1|Sock fillers
TONS|2|Really a lot
TOPS|1|Spinning toys
TOYS|1|Playroom items
TUBS|1|Bath spots
VANS|1|Movers' vehicles
VETS|2|Pet doctors
VOWS|2|Wedding promises
WEBS|1|Spiders' traps
WIGS|1|Fake hair pieces
ZOOS|1|Lion-viewing spots
ACHES|1|Dull pains
AREAS|1|Zones
BANDS|1|Concert groups
BANKS|1|Money keepers
BARNS|1|Hay storage buildings
BATHS|1|Tub soaks
BEANS|1|Chili bits
BEARS|1|Honey-loving giants
BELLS|1|School ringers
BELTS|1|Pants holders
BIKES|1|Two-wheelers
BIRDS|1|Nest builders
BOATS|1|Lake vessels
BONES|1|Skeleton pieces
BOOKS|1|Library loans
BOOTS|1|Winter footwear
BOWLS|1|Cereal holders
CAGES|1|Bird enclosures
CAKES|1|Birthday desserts
CAMPS|1|Summer tent trips
CARDS|1|Poker hand's makings
CARTS|1|Grocery pushers
CAVES|1|Bats' homes
CHEFS|1|Restaurant cooks
CHINS|1|Faces' bottoms
CLAWS|1|Crab pinchers
CLUBS|2|Members-only groups
COATS|1|Winter wear
CODES|2|Programmers' products
COINS|1|Piggy bank drops
COMBS|1|Hair detanglers
CORDS|2|Charger cables
COSTS|1|Price tag numbers
CREWS|2|Ships' teams
CROPS|2|Farmers' harvests
CUBES|2|Ice shapes
CURLS|2|Hair loops
DARTS|2|Pub-game missiles
DATES|1|Calendar squares
DEALS|1|Bargains
DESKS|1|Homework surfaces
DIMES|2|Ten-cent coins
DOCKS|2|Boat parking spots
DOLLS|1|Toy figures
DOORS|1|Knock spots
DRUMS|1|Beat keepers
DUCKS|1|Pond quackers
EDGES|1|Cliffs' rims
EXAMS|1|Final tests
EXITS|1|Ways out
FACTS|1|True statements
FARMS|1|Tractors' homes
FILMS|1|Movies
FLAGS|1|Pole flyers
FORKS|1|Salad stabbers
FORTS|2|Pillow constructions
FROGS|1|Lily pad sitters
GAMES|1|Arcade offerings
GATES|1|Airport departure spots
GEARS|2|Clockwork wheels
GIFTS|1|Wrapped surprises
GIRLS|1|Young ladies
GOALS|1|Soccer scores
GOATS|1|Bearded farm climbers
GRINS|1|Big smiles
HALLS|1|School corridors
HANDS|1|Five-finger units
HEADS|1|Hats' spots
HIKES|1|Trail walks
HILLS|1|Small mountains
HINTS|1|Helpful nudges
HIVES|2|Bee headquarters
HOLES|1|Donuts' centers
HOMES|1|Where hearts are
HOOKS|2|Coat hangers on walls
HORNS|1|Traffic honkers
HOSES|1|Garden waterers
HOURS|1|Clock units
ICONS|2|Desktop clickables
IDEAS|1|Light-bulb moments
ITEMS|2|List entries
JOKES|1|Comedians' lines
KINGS|1|Chess targets
KITES|1|Windy-day flyers
KNEES|1|Legs' hinges
KNOTS|2|Shoelace tangles
LAKES|1|Freshwater expanses
LAMPS|1|Bedside lights
LANES|1|Bowling strips
LIMES|2|Green citruses
LINES|1|Things to wait in
LIONS|1|Mane attractions
LISTS|1|Grocery reminders
LOCKS|1|Keys' partners
LOOPS|2|Circular paths
MASKS|1|Halloween faces
MAZES|1|Cornfield puzzles
MEALS|1|Breakfasts and dinners
MENUS|1|Diners' readings
MILES|1|Marathon units
MINTS|2|Breath fresheners
MOODS|1|Emotional weather states
MOONS|1|Planets' companions
MOTHS|2|Porch-light circlers
NAMES|1|Name-tag words
NECKS|1|Giraffes' long features
NESTS|1|Egg cradles
NOTES|1|Fridge reminders
OVENS|1|Bakers' boxes
PAGES|1|Book units
PAILS|2|Beach buckets
PAIRS|1|Sock sets
PARKS|1|Picnic places
PATHS|1|Garden walkways
PEAKS|2|Mountain tops
PEARS|1|Bell-shaped fruits
PILES|1|Laundry mountains
PINES|2|Evergreens with needles
PIPES|2|Plumbers' tubes
PLANS|1|Blueprints
PLOTS|2|Stories' backbones
PLUGS|2|Outlet fillers
POEMS|1|Rhyming works
POLES|2|North and South points
PONDS|1|Ducks' puddles
POOLS|1|Backyard swim spots
RACES|1|Track events
RAKES|1|Leaf gatherers
RINGS|1|Proposal jewelry
ROADS|1|Cars' paths
ROCKS|1|Climbers' walls
ROLES|2|Actors' parts
ROOFS|1|House toppers
ROOMS|1|House divisions
ROOTS|1|Tree anchors
ROPES|1|Tug-of-war needs
ROSES|1|Valentine flowers
RULES|1|Classroom guidelines
SAILS|1|Boats' sheets
SEATS|1|Places to sit
SEEDS|1|Garden starters
SHIPS|1|Ocean liners
SHOPS|1|Main Street businesses
SIDES|1|Fries, e.g.
SIGNS|1|Stop and yield, for two
SIZES|1|Small, medium, and large
SLEDS|1|Snow-day rides
SOCKS|1|Shoe liners
SONGS|1|Playlist units
SPOTS|1|Dalmatian marks
STARS|1|Night-sky twinklers
STEPS|1|Stair units
TAILS|1|Dogs' waggers
TALES|1|Stories
TANKS|2|Fish homes
TAPES|1|Gift-wrap needs
TASKS|1|To-do items
TEAMS|1|Groups of players
TENTS|1|Campers' shelters
TESTS|1|Pop quizzes' big brothers
TIRES|1|Cars' rubber rings
TOADS|2|Warty hoppers
TOOLS|1|Hammers and saws
TOWNS|1|Small cities
TRAPS|1|Mouse catchers
TRAYS|1|Cafeteria carriers
TREES|1|Trunk owners
TRIPS|1|Vacations
TUBES|2|Toothpaste holders
TUNES|1|Melodies
TWINS|1|Identical siblings
VASES|1|Flower holders
VIEWS|1|Window sceneries
VINES|2|Grapes' growers
VOTES|1|Ballot actions
WALLS|1|Picture hangers' spots
WAVES|1|Beach rollers
WEEKS|1|Seven-day stretches
WINGS|1|Birds' fliers
WIRES|2|Electricians' lines
WORDS|1|Dictionary entries
YARDS|1|Lawns' locations
YEARS|1|365-day stretches
"""
}
