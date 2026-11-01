"""Vocabulary packs, so the model learns sentence structure rather than one domain's words.

Each domain supplies boxes and how dictation refers to them, verbs, conditions and procedure
steps. Held-out test descriptions also use domains that are *not* here (education, legal,
manufacturing) to check the model generalizes beyond the vocabularies it was trained on.
"""

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Domain:
    name: str
    things: list[tuple[str, str]]          # (box name, how dictation refers to it)
    verbs: list[tuple[str, str]]           # (edge label, verb phrase before the target)
    conditions: list[tuple[str, list[str]]]  # (decision box, phrasings of the condition)
    thing_conditions: list[tuple[str, str]]  # ("{} down?", "{} is down"), filled with a box
    steps: list[tuple[str, str]]           # (box, imperative text) for subject-less procedures
    step_outcomes: list[tuple[str, list[str]]]
    front_components: list[tuple[str, str]]  # (box, phrase) that can sit "in front of" a box
    replicable: bool                       # whether "X is multiple, round robin" makes sense


SOFTWARE = Domain(
    name="software",
    things=[
        ("User", "the user"), ("Customer", "the customer"), ("Admin", "the admin"),
        ("Web App", "the web app"), ("Mobile App", "the mobile app"), ("Browser", "the browser"),
        ("API", "the API"), ("Gateway", "the gateway"), ("Load Balancer", "the load balancer"),
        ("Database", "the database"), ("Postgres", "Postgres"), ("Cache", "the cache"),
        ("Redis", "Redis"), ("Auth Service", "the auth service"), ("CDN", "the CDN"),
        ("Origin Server", "the origin server"), ("Queue", "the queue"), ("Worker", "the worker"),
        ("S3", "S3"), ("Local Disk", "local disk"), ("Search Index", "the search index"),
        ("Email Service", "the email service"), ("Payment Service", "the payment service"),
        ("Ledger", "the ledger"), ("Supplier", "the supplier"), ("Warehouse", "the warehouse"),
        ("Server", "the server"), ("Local Storage", "local storage"), ("Scheduler", "the scheduler"),
        ("Logger", "the logger"), ("Billing", "billing"), ("Inventory", "inventory"),
        ("Backup Server", "the backup server"), ("Team", "the team"), ("Support", "support"),
        ("Analytics", "analytics"), ("Notification Service", "the notification service"),
        ("Kafka", "Kafka"), ("Frontend", "the frontend"), ("Backend", "the backend"),
    ],
    verbs=[
        ("calls", "calls"), ("reads from", "reads from"), ("writes to", "writes to"),
        ("sends request", "sends a request to"), ("queries", "queries"), ("fetches from", "fetches from"),
        ("pushes to", "pushes to"), ("pulls from", "pulls from"), ("notifies", "notifies"),
        ("updates", "updates"), ("forwards to", "forwards it to"), ("emails", "emails"),
        ("uses", "uses"), ("saves to", "saves to"), ("publishes to", "publishes to"),
        ("asks", "asks"), ("checks", "checks"), ("syncs with", "syncs with"), ("logs to", "logs to"),
        ("talks to", "talks to"), ("hits", "hits"), ("goes to", "goes to"), ("charges", "charges"),
    ],
    conditions=[
        ("Cache miss?", ["there is a cache miss", "cache miss happens", "the cache misses", "it misses the cache"]),
        ("Token expired?", ["the token has expired", "the token is expired", "the session token expires"]),
        ("Stock low?", ["stock runs low", "stock is low", "inventory gets low"]),
        ("Online?", ["it is online", "the device is online", "there is a connection"]),
        ("Payment failed?", ["the payment fails", "the charge is declined", "the card is declined"]),
        ("Tests pass?", ["the tests pass", "tests are green", "all tests pass"]),
        ("Request valid?", ["the request is valid", "the input checks out", "validation passes"]),
        ("Queue full?", ["the queue is full", "the queue backs up"]),
        ("Found?", ["the record is found", "it finds the record", "there is a match"]),
        ("Server down?", ["the server is down", "the primary is down", "the service is unavailable"]),
        ("Rate limited?", ["it is rate limited", "the limit is hit", "too many requests come in"]),
        ("File too large?", ["the file is too large", "the upload is over the limit"]),
        ("Logged in?", ["the user is logged in", "there is a session"]),
        ("Retry left?", ["there are retries left", "it can still retry"]),
    ],
    thing_conditions=[
        ("{} down?", "{} is down"), ("{} full?", "{} is full"), ("{} empty?", "{} is empty"),
        ("{} timeout?", "{} times out"), ("{} unavailable?", "{} is unavailable"), ("{} miss?", "{} misses"),
    ],
    steps=[
        ("Compile code", "compile the code"), ("Lint files", "lint the files"), ("Package release", "package the release"),
        ("Publish image", "publish the image"), ("Alert on-call", "alert on-call"), ("Roll back", "roll back"),
        ("Resize image", "resize the image"), ("Upload file", "upload the file"), ("Send invoice", "send the invoice"),
        ("Charge card", "charge the card"), ("Ship order", "ship the order"), ("Email receipt", "email the receipt"),
        ("Scan file", "scan the file"), ("Quarantine file", "quarantine the file"), ("Merge branch", "merge the branch"),
        ("Open ticket", "open a ticket"), ("Back up database", "back up the database"), ("Restart service", "restart the service"),
    ],
    step_outcomes=[
        ("Succeeded?", ["it succeeds", "it works", "that goes fine"]),
        ("Passed?", ["it passes", "they pass", "the checks pass"]),
        ("Clean?", ["it is clean", "nothing is found"]),
    ],
    front_components=[
        ("Load Balancer", "load balancer"), ("Gateway", "gateway"), ("Proxy", "proxy"),
        ("Firewall", "firewall"), ("Rate Limiter", "rate limiter"), ("CDN", "CDN"), ("WAF", "WAF"),
        ("Cache", "cache"),
    ],
    replicable=True,
)

HIRING = Domain(
    name="hiring",
    things=[
        ("Candidate", "the candidate"), ("Recruiter", "the recruiter"), ("Hiring Manager", "the hiring manager"),
        ("Careers Site", "the careers site"), ("ATS", "the ATS"), ("Interview Panel", "the interview panel"),
        ("HR", "HR"), ("Coordinator", "the coordinator"), ("Referral", "the referral"),
        ("Team Lead", "the team lead"), ("Onboarding", "onboarding"), ("IT Desk", "the IT desk"),
        ("Payroll", "payroll"), ("Talent Pool", "the talent pool"), ("Agency", "the agency"),
    ],
    verbs=[
        ("applies to", "applies through"), ("sends resume", "sends the resume to"), ("screens", "screens"),
        ("schedules", "schedules time with"), ("interviews", "interviews"), ("forwards to", "passes it to"),
        ("notifies", "lets"), ("emails", "emails"), ("reviews with", "reviews it with"),
        ("hands off to", "hands it off to"), ("files in", "files it in"), ("updates", "updates"),
    ],
    conditions=[
        ("Resume matches?", ["the resume matches the role", "the resume is a fit", "the profile matches"]),
        ("Panel approves?", ["the panel approves", "the interviewers say yes", "the panel signs off"]),
        ("Offer accepted?", ["the candidate accepts", "the offer is accepted"]),
        ("Background clear?", ["the background check is clear", "the check comes back clean"]),
        ("Senior role?", ["it is a senior role", "the role is senior"]),
        ("Referral?", ["it came from a referral", "someone referred them"]),
        ("Visa needed?", ["they need a visa", "sponsorship is needed"]),
    ],
    thing_conditions=[("{} busy?", "{} is busy"), ("{} unavailable?", "{} is unavailable"), ("{} full?", "{} is full")],
    steps=[
        ("Post job", "post the job"), ("Screen resumes", "screen the resumes"), ("Phone screen", "do a phone screen"),
        ("Onsite interview", "run the onsite"), ("Debrief", "hold a debrief"), ("Make offer", "make an offer"),
        ("Check references", "check references"), ("Send rejection", "send a rejection"), ("Start onboarding", "start onboarding"),
        ("Order laptop", "order a laptop"), ("Add to pool", "add them to the pool"), ("Negotiate", "negotiate"),
    ],
    step_outcomes=[
        ("Approved?", ["it is approved", "they approve", "it goes well"]),
        ("Accepted?", ["they accept", "it is accepted"]),
        ("Strong fit?", ["they are a strong fit", "the feedback is good"]),
    ],
    front_components=[("Background Check", "background check"), ("Screening Call", "screening call"), ("Approval Step", "approval step")],
    replicable=False,
)

HEALTHCARE = Domain(
    name="healthcare",
    things=[
        ("Patient", "the patient"), ("Reception", "reception"), ("Nurse", "the nurse"), ("Doctor", "the doctor"),
        ("Lab", "the lab"), ("Pharmacy", "the pharmacy"), ("Insurance", "insurance"), ("EHR", "the EHR"),
        ("Radiology", "radiology"), ("Specialist", "the specialist"), ("Billing Office", "the billing office"),
        ("Triage", "triage"), ("Ward", "the ward"), ("Ambulance", "the ambulance"), ("Discharge Desk", "the discharge desk"),
    ],
    verbs=[
        ("checks in at", "checks in at"), ("pulls record from", "pulls the record from"), ("examines", "examines"),
        ("refers to", "refers them to"), ("sends results to", "sends the results to"), ("orders from", "orders tests from"),
        ("prescribes via", "sends a prescription to"), ("bills", "bills"), ("admits to", "admits them to"),
        ("transfers to", "transfers them to"), ("updates", "updates"), ("calls", "calls"),
    ],
    conditions=[
        ("Tests needed?", ["the doctor needs tests", "tests are needed", "more tests are required"]),
        ("Urgent?", ["it is urgent", "the case is critical", "the patient is in pain"]),
        ("Claim denied?", ["insurance denies the claim", "the claim is denied", "coverage is refused"]),
        ("Results abnormal?", ["the results are abnormal", "something shows up", "the scan looks bad"]),
        ("Insured?", ["the patient has insurance", "they are covered"]),
        ("Stable?", ["the patient is stable", "vitals look normal"]),
    ],
    thing_conditions=[("{} busy?", "{} is busy"), ("{} closed?", "{} is closed"), ("{} full?", "{} is full")],
    steps=[
        ("Take vitals", "take vitals"), ("Draw blood", "draw blood"), ("Run scan", "run a scan"),
        ("Diagnose", "make a diagnosis"), ("Write prescription", "write a prescription"), ("Schedule follow-up", "schedule a follow-up"),
        ("Admit patient", "admit the patient"), ("Discharge patient", "discharge the patient"), ("Refer out", "refer them out"),
        ("Update chart", "update the chart"), ("Bill visit", "bill the visit"), ("Call family", "call the family"),
    ],
    step_outcomes=[
        ("Normal?", ["it is normal", "everything looks fine"]),
        ("Improving?", ["they improve", "it gets better"]),
        ("Confirmed?", ["it is confirmed", "the diagnosis holds"]),
    ],
    front_components=[("Triage", "triage desk"), ("Reception", "reception desk"), ("Screening", "screening station")],
    replicable=True,
)

LOGISTICS = Domain(
    name="logistics",
    things=[
        ("Seller", "the seller"), ("Depot", "the depot"), ("Courier", "the courier"), ("Customer", "the customer"),
        ("Locker", "the locker"), ("Customs", "customs"), ("Sorting Center", "the sorting center"),
        ("Truck", "the truck"), ("Carrier", "the carrier"), ("Returns Desk", "the returns desk"),
        ("Tracking System", "the tracking system"), ("Port", "the port"), ("Driver", "the driver"),
        ("Distribution Hub", "the distribution hub"), ("Post Office", "the post office"),
    ],
    verbs=[
        ("ships to", "ships the parcel to"), ("hands to", "hands it to"), ("delivers to", "delivers to"),
        ("sorts for", "sorts it for"), ("scans into", "scans it into"), ("loads onto", "loads it onto"),
        ("routes via", "routes it via"), ("returns to", "returns it to"), ("notifies", "notifies"),
        ("picks up from", "picks up from"), ("drops at", "drops it at"), ("inspects for", "inspects it for"),
    ],
    conditions=[
        ("Someone home?", ["someone is home", "the customer is home", "there is someone to sign"]),
        ("International?", ["the parcel is international", "it ships abroad", "it crosses a border"]),
        ("Damaged?", ["the parcel is damaged", "the box is broken"]),
        ("Address valid?", ["the address is valid", "the address checks out"]),
        ("Oversized?", ["the parcel is oversized", "it is too big"]),
        ("Express?", ["it is express", "the customer paid for express"]),
    ],
    thing_conditions=[("{} full?", "{} is full"), ("{} closed?", "{} is closed"), ("{} delayed?", "{} is delayed")],
    steps=[
        ("Pack order", "pack the order"), ("Print label", "print the label"), ("Weigh parcel", "weigh the parcel"),
        ("Book pickup", "book a pickup"), ("Clear customs", "clear customs"), ("Load truck", "load the truck"),
        ("Deliver parcel", "deliver the parcel"), ("Leave card", "leave a card"), ("Return to sender", "return it to sender"),
        ("Refund customer", "refund the customer"), ("File claim", "file a claim"), ("Reschedule", "reschedule delivery"),
    ],
    step_outcomes=[
        ("Delivered?", ["it is delivered", "the delivery works"]),
        ("Cleared?", ["it clears", "customs releases it"]),
        ("Intact?", ["it arrives intact", "nothing is damaged"]),
    ],
    front_components=[("Customs", "customs check"), ("Scanner", "scanner"), ("Weighing Station", "weighing station")],
    replicable=True,
)

FINANCE = Domain(
    name="finance",
    things=[
        ("Employee", "the employee"), ("Manager", "the manager"), ("Finance", "finance"), ("Payroll", "payroll"),
        ("Expense Tool", "the expense tool"), ("Controller", "the controller"), ("CFO", "the CFO"),
        ("Vendor", "the vendor"), ("Procurement", "procurement"), ("Accounts Payable", "accounts payable"),
        ("Bank", "the bank"), ("Auditor", "the auditor"), ("ERP", "the ERP"), ("Treasury", "treasury"),
    ],
    verbs=[
        ("submits to", "submits it to"), ("approves for", "approves it for"), ("reviews", "reviews"),
        ("escalates to", "escalates it to"), ("pays", "pays"), ("records in", "records it in"),
        ("requests from", "requests a quote from"), ("invoices", "invoices"), ("reimburses", "reimburses"),
        ("flags to", "flags it to"), ("sends to", "sends it to"), ("reconciles with", "reconciles it with"),
    ],
    conditions=[
        ("Over limit?", ["the amount is over the limit", "it is over budget", "it exceeds the threshold"]),
        ("Receipt attached?", ["a receipt is attached", "the receipt is there"]),
        ("Approved?", ["the manager approves", "it is approved", "they sign off"]),
        ("Duplicate?", ["it is a duplicate", "the invoice was already paid"]),
        ("New vendor?", ["the vendor is new", "it is a first-time vendor"]),
        ("Month end?", ["it is month end", "the books are closing"]),
    ],
    thing_conditions=[("{} away?", "{} is away"), ("{} busy?", "{} is busy"), ("{} locked?", "{} is locked")],
    steps=[
        ("Submit expense", "submit the expense"), ("Attach receipt", "attach the receipt"), ("Approve spend", "approve the spend"),
        ("Pay invoice", "pay the invoice"), ("Record entry", "record the entry"), ("Reconcile account", "reconcile the account"),
        ("Close books", "close the books"), ("Request quote", "request a quote"), ("Issue PO", "issue a PO"),
        ("Reject claim", "reject the claim"), ("Reimburse", "reimburse the employee"), ("Audit sample", "audit a sample"),
    ],
    step_outcomes=[
        ("Matched?", ["it matches", "the numbers match"]),
        ("Approved?", ["it is approved", "they approve"]),
        ("Balanced?", ["it balances", "the books balance"]),
    ],
    front_components=[("Approval Step", "approval step"), ("Compliance Check", "compliance check"), ("Fraud Check", "fraud check")],
    replicable=False,
)

KITCHEN = Domain(
    name="kitchen",
    things=[
        ("Server", "the server"), ("Kitchen", "the kitchen"), ("Chef", "the chef"), ("Line Cook", "the line cook"),
        ("Pass", "the pass"), ("Guest", "the guest"), ("POS", "the POS"), ("Bar", "the bar"),
        ("Pantry", "the pantry"), ("Dishwasher", "the dishwasher"), ("Host", "the host"), ("Expo", "expo"),
        ("Supplier", "the supplier"), ("Walk-in", "the walk-in"),
    ],
    verbs=[
        ("takes order from", "takes the order from"), ("sends ticket to", "sends the ticket to"), ("cooks for", "cooks for"),
        ("plates for", "plates it for"), ("serves", "serves"), ("rings up on", "rings it up on"),
        ("fetches from", "fetches it from"), ("orders from", "orders more from"), ("hands to", "hands it to"),
        ("seats", "seats"), ("tells", "tells"), ("stocks", "stocks"),
    ],
    conditions=[
        ("Allergy?", ["the guest has an allergy", "there is an allergy"]),
        ("Out of stock?", ["an ingredient is out", "they run out", "the dish is eighty-sixed"]),
        ("Rush?", ["it is a rush", "the kitchen is slammed"]),
        ("Drinks ordered?", ["drinks are ordered", "the table orders drinks"]),
        ("Table ready?", ["a table is ready", "there is a free table"]),
    ],
    thing_conditions=[("{} busy?", "{} is busy"), ("{} closed?", "{} is closed")],
    steps=[
        ("Preheat oven", "preheat the oven"), ("Mix batter", "mix the batter"), ("Bake", "bake it"),
        ("Cool", "let it cool"), ("Frost", "frost it"), ("Chop vegetables", "chop the vegetables"),
        ("Sear meat", "sear the meat"), ("Simmer sauce", "simmer the sauce"), ("Plate dish", "plate the dish"),
        ("Taste", "taste it"), ("Season", "season it"), ("Rest dough", "rest the dough"),
    ],
    step_outcomes=[
        ("Done?", ["it is done", "it is cooked through"]),
        ("Thick enough?", ["it is thick enough", "the sauce coats the spoon"]),
        ("Golden?", ["it is golden", "it browns"]),
    ],
    front_components=[("Host Stand", "host stand"), ("Expo", "expo station"), ("Waitlist", "waitlist")],
    replicable=False,
)

def load_generated_domains() -> list[Domain]:
    """Extra packs from generate_domains.py, if it has been run."""
    path = Path(__file__).parent / "generated_domains.json"
    return [Domain(**fields) for fields in json.loads(path.read_text())] if path.exists() else []


GENERATED_DOMAINS = load_generated_domains()
DOMAINS = [SOFTWARE, HIRING, HEALTHCARE, LOGISTICS, FINANCE, KITCHEN, *GENERATED_DOMAINS]
# Software stays about 40% of stories, since that is termaid's main use.
SOFTWARE_SHARE = 0.4
OTHER_COUNT = len(DOMAINS) - 1
DOMAIN_WEIGHTS = [round(OTHER_COUNT * SOFTWARE_SHARE / (1 - SOFTWARE_SHARE)), *[1] * OTHER_COUNT]
