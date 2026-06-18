import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/course.dart';
import '../models/learner.dart';
import '../models/lesson.dart';
import '../models/question.dart';
import '../models/ticket.dart';
import '../../core/widgets/course_thumb.dart';

// ─── Role ────────────────────────────────────────────────────────────────────
enum UserRole { learner, admin }

final roleProvider = StateProvider<UserRole>((ref) => UserRole.learner);

// ─── Mock Courses ─────────────────────────────────────────────────────────────
final mockCourses = [
  const Course(
    id: 'c1',
    title: 'Working at Heights — Foundation',
    desc: 'Core principles of fall protection for construction and industrial environments.',
    cat: 'FALL PROTECTION',
    style: CourseStyle.animated,
    status: 'published',
    level: 'Beginner',
    lessons: 8,
    mins: 95,
    progress: 62,
    learners: 284,
    rating: 4.8,
    certified: false,
    code: 'WAH-181',
  ),
  const Course(
    id: 'c2',
    title: 'Harness Inspection & Fit',
    desc: 'Step-by-step inspection procedures and correct harness fitting techniques.',
    cat: 'EQUIPMENT',
    style: CourseStyle.whiteboard,
    status: 'published',
    level: 'Intermediate',
    lessons: 6,
    mins: 70,
    progress: 100,
    learners: 196,
    rating: 4.7,
    certified: true,
    code: 'EQP-042',
  ),
  const Course(
    id: 'c3',
    title: 'Anchor Point Selection',
    desc: 'Identifying and using correct anchor points for fall arrest systems.',
    cat: 'FALL PROTECTION',
    style: CourseStyle.claude,
    status: 'published',
    level: 'Advanced',
    lessons: 10,
    mins: 120,
    progress: 0,
    learners: 142,
    rating: 4.9,
    certified: false,
    code: 'WAH-205',
  ),
  const Course(
    id: 'c4',
    title: 'Emergency Rescue Procedures',
    desc: 'Suspended worker rescue protocols and emergency response planning.',
    cat: 'EMERGENCY',
    style: CourseStyle.hybrid,
    status: 'published',
    level: 'Advanced',
    lessons: 12,
    mins: 145,
    progress: 30,
    learners: 98,
    rating: 4.6,
    certified: false,
    code: 'EMR-088',
  ),
  const Course(
    id: 'c5',
    title: 'Site Safety Fundamentals',
    desc: 'Overview of hazard identification and site safety management systems.',
    cat: 'SITE SAFETY',
    style: CourseStyle.animated,
    status: 'published',
    level: 'Beginner',
    lessons: 7,
    mins: 80,
    progress: 0,
    learners: 356,
    rating: 4.5,
    certified: false,
    code: 'SIT-011',
  ),
  const Course(
    id: 'c6',
    title: 'Scaffolding Safety',
    desc: 'Safe erection, use, and dismantling of scaffolding structures.',
    cat: 'EQUIPMENT',
    style: CourseStyle.whiteboard,
    status: 'draft',
    level: 'Intermediate',
    lessons: 9,
    mins: 110,
    progress: 0,
    learners: 0,
    rating: 0,
    certified: false,
    code: 'SCF-033',
  ),
];

final coursesProvider = Provider<List<Course>>((ref) => mockCourses);

// ─── Mock Lessons ─────────────────────────────────────────────────────────────
final mockLessons = [
  // c1 — Working at Heights Foundation (8 lessons, 62% progress)
  const CourseLesson(id: 'l1_1', courseId: 'c1', module: 'Why Falls Happen', moduleNum: 1, title: 'The Cost of a Fall',              durationSecs: 540,  completed: true,  savedPositionSecs: 540),
  const CourseLesson(id: 'l1_2', courseId: 'c1', module: 'Why Falls Happen', moduleNum: 1, title: 'Hierarchy of Fall Controls',      durationSecs: 720,  completed: true,  savedPositionSecs: 720),
  const CourseLesson(id: 'l1_3', courseId: 'c1', module: 'Why Falls Happen', moduleNum: 1, title: 'Recognising Height Hazards',      durationSecs: 660,  completed: true,  savedPositionSecs: 660),
  const CourseLesson(id: 'l1_4', courseId: 'c1', module: 'Your Equipment',   moduleNum: 2, title: 'Full-Body Harness Anatomy',       durationSecs: 840,  completed: true,  savedPositionSecs: 840),
  const CourseLesson(id: 'l1_5', courseId: 'c1', module: 'Your Equipment',   moduleNum: 2, title: 'Lanyards & Energy Absorbers',     durationSecs: 600,  completed: false, savedPositionSecs: 135),
  const CourseLesson(id: 'l1_6', courseId: 'c1', module: 'Your Equipment',   moduleNum: 2, title: 'Anchor Points & Lifelines',       durationSecs: 780,  completed: false, savedPositionSecs: 0),
  const CourseLesson(id: 'l1_7', courseId: 'c1', module: 'Working Safely',   moduleNum: 3, title: 'Pre-Use Inspection Checklist',    durationSecs: 480,  completed: false, savedPositionSecs: 0),
  const CourseLesson(id: 'l1_8', courseId: 'c1', module: 'Working Safely',   moduleNum: 3, title: 'Emergency Rescue Procedures',     durationSecs: 900,  completed: false, savedPositionSecs: 0),
  // c2 — Harness Inspection & Fit (6 lessons, 100%)
  const CourseLesson(id: 'l2_1', courseId: 'c2', module: 'Fundamentals',     moduleNum: 1, title: 'Introduction to Harness Types',   durationSecs: 480,  completed: true,  savedPositionSecs: 480),
  const CourseLesson(id: 'l2_2', courseId: 'c2', module: 'Fundamentals',     moduleNum: 1, title: 'Webbing & Hardware Components',   durationSecs: 540,  completed: true,  savedPositionSecs: 540),
  const CourseLesson(id: 'l2_3', courseId: 'c2', module: 'Inspection',       moduleNum: 2, title: 'Pre-Use Inspection Protocol',     durationSecs: 600,  completed: true,  savedPositionSecs: 600),
  const CourseLesson(id: 'l2_4', courseId: 'c2', module: 'Inspection',       moduleNum: 2, title: 'Identifying Defects & Damage',    durationSecs: 660,  completed: true,  savedPositionSecs: 660),
  const CourseLesson(id: 'l2_5', courseId: 'c2', module: 'Fitting',          moduleNum: 3, title: 'Donning & Adjustment Techniques', durationSecs: 720,  completed: true,  savedPositionSecs: 720),
  const CourseLesson(id: 'l2_6', courseId: 'c2', module: 'Fitting',          moduleNum: 3, title: 'Fit Check & Final Verification',  durationSecs: 540,  completed: true,  savedPositionSecs: 540),
  // c4 — Emergency Rescue (12 lessons, 30% = ~4 done)
  const CourseLesson(id: 'l4_1', courseId: 'c4', module: 'Fundamentals',     moduleNum: 1, title: 'Suspended Worker Physiology',     durationSecs: 600,  completed: true,  savedPositionSecs: 600),
  const CourseLesson(id: 'l4_2', courseId: 'c4', module: 'Fundamentals',     moduleNum: 1, title: 'Rescue Planning Principles',      durationSecs: 720,  completed: true,  savedPositionSecs: 720),
  const CourseLesson(id: 'l4_3', courseId: 'c4', module: 'Procedures',       moduleNum: 2, title: 'Non-Entry Rescue Methods',        durationSecs: 840,  completed: true,  savedPositionSecs: 840),
  const CourseLesson(id: 'l4_4', courseId: 'c4', module: 'Procedures',       moduleNum: 2, title: 'Rope Descent Rescue',             durationSecs: 900,  completed: false, savedPositionSecs: 180),
  const CourseLesson(id: 'l4_5', courseId: 'c4', module: 'Procedures',       moduleNum: 2, title: 'Aerial Work Platform Rescue',     durationSecs: 780,  completed: false, savedPositionSecs: 0),
  const CourseLesson(id: 'l4_6', courseId: 'c4', module: 'Equipment',        moduleNum: 3, title: 'Rescue Kit Inspection',           durationSecs: 540,  completed: false, savedPositionSecs: 0),
];

final lessonsProvider = Provider<List<CourseLesson>>((ref) => mockLessons);

// ─── Mock Learners ────────────────────────────────────────────────────────────
final mockLearners = [
  const Learner(
    id: 'l1', name: 'James Harrington', email: 'james.h@example.com',
    enrolled: 4, progress: 72, lastActive: '2h ago', time: '16h 10m',
    assessments: 3, status: 'Active',
  ),
  const Learner(
    id: 'l2', name: 'Sarah Mitchell', email: 'sarah.m@example.com',
    enrolled: 6, progress: 91, lastActive: '1d ago', time: '28h 40m',
    assessments: 5, status: 'Active',
  ),
  const Learner(
    id: 'l3', name: 'Carlos Rivera', email: 'carlos.r@example.com',
    enrolled: 2, progress: 34, lastActive: '5d ago', time: '8h 20m',
    assessments: 1, status: 'Inactive',
  ),
  const Learner(
    id: 'l4', name: 'Priya Nair', email: 'priya.n@example.com',
    enrolled: 3, progress: 58, lastActive: '3h ago', time: '12h 05m',
    assessments: 2, status: 'Active',
  ),
  const Learner(
    id: 'l5', name: 'Tom Fletcher', email: 'tom.f@example.com',
    enrolled: 1, progress: 0, lastActive: 'Never', time: '0m',
    assessments: 0, status: 'Pending',
  ),
];

final learnersProvider = Provider<List<Learner>>((ref) => mockLearners);

// ─── Mock Questions ───────────────────────────────────────────────────────────
final mockQuestions = [
  const Question(
    id: 'q1',
    q: 'What is the minimum breaking strength required for a personal fall arrest anchor point?',
    opts: ['2,500 lbs (11 kN)', '3,600 lbs (16 kN)', '5,000 lbs (22 kN)', '10,000 lbs (44 kN)'],
    a: 2,
    type: 'mcq',
    topic: 'Anchor Points',
    lesson: 'Module 2 — Lesson 3',
    points: 10,
    why: 'OSHA requires a minimum of 5,000 lbs per attached worker, or the system must be certified by a qualified person.',
  ),
  const Question(
    id: 'q2',
    q: 'A full-body harness should be inspected before each use.',
    opts: ['True', 'False'],
    a: 0,
    type: 'truefalse',
    topic: 'Equipment Inspection',
    lesson: 'Module 1 — Lesson 2',
    points: 5,
    why: 'Pre-use inspections identify defects that could cause failure during a fall event.',
  ),
  const Question(
    id: 'q3',
    q: 'Which component connects the harness D-ring to the anchor point?',
    opts: ['Carabiner', 'Self-retracting lifeline', 'Lanyard or connecting subsystem', 'Body belt'],
    a: 2,
    type: 'mcq',
    topic: 'System Components',
    lesson: 'Module 2 — Lesson 1',
    points: 10,
    why: 'The connecting subsystem (lanyard, SRL, or rope grab) is the link between the harness and the anchor.',
  ),
  const Question(
    id: 'q4',
    q: 'What is the maximum free-fall distance allowed in a personal fall arrest system?',
    opts: ['2 feet (0.6 m)', '4 feet (1.2 m)', '6 feet (1.8 m)', '10 feet (3 m)'],
    a: 2,
    type: 'mcq',
    topic: 'Fall Clearance',
    lesson: 'Module 3 — Lesson 2',
    points: 10,
    why: 'OSHA 1926.502 limits free-fall to 6 feet (1.8 m) to reduce injury forces.',
  ),
  const Question(
    id: 'q5',
    q: 'Describe the correct procedure for donning (putting on) a full-body harness.',
    opts: [],
    a: 0,
    type: 'descriptive',
    topic: 'Equipment Use',
    lesson: 'Module 1 — Lesson 3',
    points: 20,
    why: 'Proper donning ensures the harness distributes fall forces correctly across the body.',
  ),
  const Question(
    id: 'q6',
    q: 'Which of these inspection findings requires removing a harness from service?',
    opts: [
      'Minor surface dirt that wipes off',
      'Slight colour fading from UV exposure',
      'Cut or frayed webbing',
      'Stiff buckle that operates correctly',
    ],
    a: 2,
    type: 'scenario',
    topic: 'Equipment Inspection',
    lesson: 'Module 1 — Lesson 2',
    points: 15,
    why: 'Cut or frayed webbing critically reduces harness strength and must be removed immediately.',
  ),
];

final questionsProvider = Provider<List<Question>>((ref) => mockQuestions);

// ─── Mock Tickets ─────────────────────────────────────────────────────────────
final mockTickets = [
  Ticket(
    id: 'TK-1042',
    subject: 'Cannot access certificate for WAH-181',
    category: 'Certificates',
    priority: 'High',
    status: 'Open',
    learnerName: 'James Harrington',
    email: 'james.h@example.com',
    date: '10 Jun 2026',
    desc: 'I completed the Working at Heights Foundation course 3 days ago and passed the assessment with 88%, but my certificate is not showing up in the Certificates section. Can you please help?',
    replies: [],
  ),
  Ticket(
    id: 'TK-1041',
    subject: 'Video playback freezing on Lesson 4',
    category: 'Technical',
    priority: 'Medium',
    status: 'In Progress',
    learnerName: 'Priya Nair',
    email: 'priya.n@example.com',
    date: '9 Jun 2026',
    desc: 'The lesson video for Module 2, Lesson 4 freezes after the knowledge check. I have tried refreshing and using a different browser.',
    replies: [
      const Reply(
        id: 'r1',
        author: 'Support Team',
        body: 'Hi Priya, thank you for reporting this. We are investigating the issue with the video player. We will update you within 24 hours.',
        time: '9 Jun 2026, 14:30',
        isAdmin: true,
      ),
    ],
  ),
  Ticket(
    id: 'TK-1039',
    subject: 'Assessment retake not available',
    category: 'Assessments',
    priority: 'Low',
    status: 'Resolved',
    learnerName: 'Sarah Mitchell',
    email: 'sarah.m@example.com',
    date: '7 Jun 2026',
    desc: 'The retake button is greyed out even though I have attempts remaining according to the course settings.',
    replies: [],
  ),
];

final ticketsProvider =
    StateNotifierProvider<TicketsNotifier, List<Ticket>>((ref) {
  return TicketsNotifier(mockTickets);
});

class TicketsNotifier extends StateNotifier<List<Ticket>> {
  TicketsNotifier(super.initial);

  void updateStatus(String id, String newStatus) {
    state = [
      for (final t in state)
        if (t.id == id)
          Ticket(
            id: t.id,
            subject: t.subject,
            category: t.category,
            priority: t.priority,
            status: newStatus,
            learnerName: t.learnerName,
            email: t.email,
            date: t.date,
            desc: t.desc,
            replies: t.replies,
          )
        else
          t
    ];
  }

  void addReply(String ticketId, Reply reply) {
    state = [
      for (final t in state)
        if (t.id == ticketId)
          Ticket(
            id: t.id,
            subject: t.subject,
            category: t.category,
            priority: t.priority,
            status: t.status,
            learnerName: t.learnerName,
            email: t.email,
            date: t.date,
            desc: t.desc,
            replies: [...t.replies, reply],
          )
        else
          t
    ];
  }
}

// ─── Assessment state ─────────────────────────────────────────────────────────
class AssessmentState {
  final Map<int, int> answers; // questionIndex -> selectedOptionIndex
  final Set<int> flagged;
  final int currentIndex;
  final bool submitted;

  const AssessmentState({
    this.answers = const {},
    this.flagged = const {},
    this.currentIndex = 0,
    this.submitted = false,
  });

  AssessmentState copyWith({
    Map<int, int>? answers,
    Set<int>? flagged,
    int? currentIndex,
    bool? submitted,
  }) =>
      AssessmentState(
        answers: answers ?? this.answers,
        flagged: flagged ?? this.flagged,
        currentIndex: currentIndex ?? this.currentIndex,
        submitted: submitted ?? this.submitted,
      );
}

final assessmentProvider =
    StateNotifierProvider.autoDispose<AssessmentNotifier, AssessmentState>(
        (ref) => AssessmentNotifier());

class AssessmentNotifier extends StateNotifier<AssessmentState> {
  AssessmentNotifier() : super(const AssessmentState());

  void answer(int qIdx, int optIdx) {
    state = state.copyWith(answers: {...state.answers, qIdx: optIdx});
  }

  void toggleFlag(int qIdx) {
    final flagged = Set<int>.from(state.flagged);
    if (flagged.contains(qIdx)) {
      flagged.remove(qIdx);
    } else {
      flagged.add(qIdx);
    }
    state = state.copyWith(flagged: flagged);
  }

  void goTo(int idx) => state = state.copyWith(currentIndex: idx);

  void submit() => state = state.copyWith(submitted: true);

  void reset() => state = const AssessmentState();
}
