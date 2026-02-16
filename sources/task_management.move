/// Module: task_management_system
/// A comprehensive task management and reward system on the Sui blockchain.
/// Users can create tasks, assign them, complete them, and earn reward points.
/// Points accumulate toward automatic level-ups based on configurable thresholds.
module task_management_system::task_management {

    // ===== Imports =====
    use std::string::String;
    use sui::event;
    use sui::package;
    use sui::display;

    // ===== Error Constants =====

    /// Error when a non-admin tries to perform an admin action
    const ENotAdmin: u64 = 0;
    /// Error when trying to interact with a task that is already completed
    const ETaskAlreadyCompleted: u64 = 1;
    /// Error when the assignee does not match the expected address
    const ENotAssignee: u64 = 2;
    /// Error when trying to complete a task that has no assignee
    const ETaskNotAssigned: u64 = 3;
    /// Error when reward points are set to zero
    const EInvalidRewardPoints: u64 = 4;
    /// Error when the title string is empty
    const EEmptyTitle: u64 = 5;
    /// Error when trying to assign a task that already has an assignee
    const ETaskAlreadyAssigned: u64 = 6;
    /// Error when the caller is not the task creator
    const ENotCreator: u64 = 7;

    // ===== Constants =====

    /// Task status: Pending (waiting to be completed)
    const STATUS_PENDING: u8 = 0;
    /// Task status: Completed
    const STATUS_COMPLETED: u8 = 1;

    /// Points required to reach Level 2
    const LEVEL_2_THRESHOLD: u64 = 100;
    /// Points required to reach Level 3
    const LEVEL_3_THRESHOLD: u64 = 300;
    /// Points required to reach Level 4
    const LEVEL_4_THRESHOLD: u64 = 600;
    /// Points required to reach Level 5
    const LEVEL_5_THRESHOLD: u64 = 1000;

    // ===== One Time Witness =====

    /// OTW struct for claiming Publisher and setting up Display
    public struct TASK_MANAGEMENT has drop {}

    // ===== Structs =====

    /// Admin capability - grants admin privileges to the holder
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Represents a task that can be created, assigned, and completed.
    /// Tasks are owned objects that live in the creator's account.
    public struct Task has key, store {
        id: UID,
        /// Title of the task
        title: String,
        /// Detailed description of what needs to be done
        description: String,
        /// Number of reward points awarded upon completion
        reward_points: u64,
        /// Current status: 0 = Pending, 1 = Completed
        status: u8,
        /// Address of the user who created this task
        creator: address,
        /// Address of the user assigned to this task (if any)
        assignee: Option<address>,
    }

    /// Tracks a user's progress, points, and level.
    /// Each user has one profile as a shared object.
    public struct UserProfile has key, store {
        id: UID,
        /// The wallet address of this user
        owner: address,
        /// Total number of tasks this user has completed
        total_tasks_completed: u64,
        /// Total reward points earned across all tasks
        total_points_earned: u64,
        /// Current level (starts at 1, max 5)
        level: u8,
    }

    /// Shared object that acts as a registry for the task board.
    /// Stores global statistics and references.
    public struct TaskBoard has key {
        id: UID,
        /// Total number of tasks ever created on the platform
        total_tasks_created: u64,
        /// Total number of tasks completed on the platform
        total_tasks_completed: u64,
    }

    // ===== Event Structs =====

    /// Emitted when a new task is created
    public struct TaskCreated has copy, drop {
        task_id: ID,
        title: String,
        reward_points: u64,
        creator: address,
    }

    /// Emitted when a task is assigned to a user
    public struct TaskAssigned has copy, drop {
        task_id: ID,
        assignee: address,
        assigned_by: address,
    }

    /// Emitted when a task is completed
    public struct TaskCompleted has copy, drop {
        task_id: ID,
        completer: address,
        points_awarded: u64,
    }

    /// Emitted when a user levels up
    public struct UserLeveledUp has copy, drop {
        user: address,
        new_level: u8,
        total_points: u64,
    }

    /// Emitted when a new user profile is created
    public struct ProfileCreated has copy, drop {
        user: address,
        profile_id: ID,
    }

    // ===== Init Function (OTW Pattern) =====

    /// Module initializer. Uses the One Time Witness to claim Publisher
    /// and set up Display objects for Task and UserProfile structs.
    fun init(otw: TASK_MANAGEMENT, ctx: &mut TxContext) {
        // Claim the Publisher using the OTW
        let publisher = package::claim(otw, ctx);

        // Set up Display for Task
        let task_keys = vector[
            b"name".to_string(),
            b"description".to_string(),
            b"creator".to_string(),
        ];
        let task_values = vector[
            b"{title}".to_string(),
            b"{description}".to_string(),
            b"Created by {creator}".to_string(),
        ];
        let mut task_display = display::new_with_fields<Task>(
            &publisher, task_keys, task_values, ctx,
        );
        display::update_version(&mut task_display);

        // Set up Display for UserProfile
        let profile_keys = vector[
            b"name".to_string(),
            b"description".to_string(),
        ];
        let profile_values = vector[
            b"Task Manager Profile".to_string(),
            b"Level {level} | Points: {total_points_earned}".to_string(),
        ];
        let mut profile_display = display::new_with_fields<UserProfile>(
            &publisher, profile_keys, profile_values, ctx,
        );
        display::update_version(&mut profile_display);

        // Create the shared TaskBoard
        let task_board = TaskBoard {
            id: object::new(ctx),
            total_tasks_created: 0,
            total_tasks_completed: 0,
        };

        // Create AdminCap for the deployer
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };

        // Transfer objects
        transfer::public_transfer(publisher, ctx.sender());
        transfer::public_transfer(task_display, ctx.sender());
        transfer::public_transfer(profile_display, ctx.sender());
        transfer::public_transfer(admin_cap, ctx.sender());
        transfer::share_object(task_board);
    }

    // ===== Public Functions =====

    /// Creates a new user profile. Each user should create one profile
    /// to track their task completion stats and level.
    public fun create_profile(ctx: &mut TxContext) {
        let sender = ctx.sender();
        let profile = UserProfile {
            id: object::new(ctx),
            owner: sender,
            total_tasks_completed: 0,
            total_points_earned: 0,
            level: 1,
        };

        event::emit(ProfileCreated {
            user: sender,
            profile_id: object::id(&profile),
        });

        transfer::public_transfer(profile, sender);
    }

    /// Creates a new task with a title, description, and reward points.
    /// The task is transferred to the creator and tracked on the TaskBoard.
    public fun create_task(
        board: &mut TaskBoard,
        title: String,
        description: String,
        reward_points: u64,
        ctx: &mut TxContext,
    ) {
        // Validate inputs
        assert!(title.length() > 0, EEmptyTitle);
        assert!(reward_points > 0, EInvalidRewardPoints);

        let sender = ctx.sender();

        let task = Task {
            id: object::new(ctx),
            title,
            description,
            reward_points,
            status: STATUS_PENDING,
            creator: sender,
            assignee: option::none(),
        };

        // Emit event
        event::emit(TaskCreated {
            task_id: object::id(&task),
            title: task.title,
            reward_points,
            creator: sender,
        });

        // Update board stats
        board.total_tasks_created = board.total_tasks_created + 1;

        // Transfer the task to the creator
        transfer::public_transfer(task, sender);
    }

    /// Assigns a task to a specific user. Only the task creator can assign tasks.
    /// A task can only be assigned once (unless reassigned by admin).
    public fun assign_task(
        task: &mut Task,
        assignee: address,
        ctx: &mut TxContext,
    ) {
        let sender = ctx.sender();

        // Only the creator can assign
        assert!(sender == task.creator, ENotCreator);
        // Task must not already be completed
        assert!(task.status != STATUS_COMPLETED, ETaskAlreadyCompleted);
        // Task must not already be assigned
        assert!(task.assignee.is_none(), ETaskAlreadyAssigned);

        task.assignee = option::some(assignee);

        event::emit(TaskAssigned {
            task_id: object::id(task),
            assignee,
            assigned_by: sender,
        });
    }

    /// Completes a task and awards reward points to the assignee's profile.
    /// The assignee must be the one calling this function.
    /// Automatically checks for level-up after awarding points.
    public fun complete_task(
        task: &mut Task,
        board: &mut TaskBoard,
        profile: &mut UserProfile,
        ctx: &mut TxContext,
    ) {
        let sender = ctx.sender();

        // Task must not already be completed
        assert!(task.status != STATUS_COMPLETED, ETaskAlreadyCompleted);
        // Task must have an assignee
        assert!(task.assignee.is_some(), ETaskNotAssigned);
        // Caller must be the assignee
        assert!(*task.assignee.borrow() == sender, ENotAssignee);

        // Mark task as completed
        task.status = STATUS_COMPLETED;

        // Award points to the user profile
        let points = task.reward_points;
        profile.total_tasks_completed = profile.total_tasks_completed + 1;
        profile.total_points_earned = profile.total_points_earned + points;

        // Update board stats
        board.total_tasks_completed = board.total_tasks_completed + 1;

        // Emit completion event
        event::emit(TaskCompleted {
            task_id: object::id(task),
            completer: sender,
            points_awarded: points,
        });

        // Check for level up
        check_level_up(profile);
    }

    /// Admin function: forcefully reassign a task to a different user.
    /// Requires AdminCap to execute.
    public fun admin_reassign_task(
        _admin: &AdminCap,
        task: &mut Task,
        new_assignee: address,
    ) {
        assert!(task.status != STATUS_COMPLETED, ETaskAlreadyCompleted);
        task.assignee = option::some(new_assignee);

        event::emit(TaskAssigned {
            task_id: object::id(task),
            assignee: new_assignee,
            assigned_by: @0x0, // admin action marker
        });
    }

    // ===== Getter Functions =====

    /// Returns the title of a task
    public fun get_task_title(task: &Task): String {
        task.title
    }

    /// Returns the description of a task
    public fun get_task_description(task: &Task): String {
        task.description
    }

    /// Returns the reward points of a task
    public fun get_task_reward_points(task: &Task): u64 {
        task.reward_points
    }

    /// Returns the current status of a task (0 = Pending, 1 = Completed)
    public fun get_task_status(task: &Task): u8 {
        task.status
    }

    /// Returns the creator address of a task
    public fun get_task_creator(task: &Task): address {
        task.creator
    }

    /// Returns the assignee of a task (if any)
    public fun get_task_assignee(task: &Task): Option<address> {
        task.assignee
    }

    /// Checks if a task is completed
    public fun is_task_completed(task: &Task): bool {
        task.status == STATUS_COMPLETED
    }

    /// Checks if a task has been assigned
    public fun is_task_assigned(task: &Task): bool {
        task.assignee.is_some()
    }

    /// Returns the total tasks completed by a user
    public fun get_profile_tasks_completed(profile: &UserProfile): u64 {
        profile.total_tasks_completed
    }

    /// Returns the total points earned by a user
    public fun get_profile_points(profile: &UserProfile): u64 {
        profile.total_points_earned
    }

    /// Returns the current level of a user
    public fun get_profile_level(profile: &UserProfile): u8 {
        profile.level
    }

    /// Returns the owner address of a profile
    public fun get_profile_owner(profile: &UserProfile): address {
        profile.owner
    }

    /// Returns total tasks created on the board
    public fun get_board_total_created(board: &TaskBoard): u64 {
        board.total_tasks_created
    }

    /// Returns total tasks completed on the board
    public fun get_board_total_completed(board: &TaskBoard): u64 {
        board.total_tasks_completed
    }

    // ===== Internal Helper Functions =====

    /// Checks if the user's points have crossed a level threshold
    /// and levels them up accordingly. Emits UserLeveledUp event if level changes.
    fun check_level_up(profile: &mut UserProfile) {
        let points = profile.total_points_earned;
        let old_level = profile.level;

        // Determine new level based on points
        let new_level = if (points >= LEVEL_5_THRESHOLD) {
            5
        } else if (points >= LEVEL_4_THRESHOLD) {
            4
        } else if (points >= LEVEL_3_THRESHOLD) {
            3
        } else if (points >= LEVEL_2_THRESHOLD) {
            2
        } else {
            1
        };

        // Only emit event and update if level actually changed
        if (new_level > old_level) {
            profile.level = new_level;
            event::emit(UserLeveledUp {
                user: profile.owner,
                new_level,
                total_points: points,
            });
        };
    }

    // ===== Test-Only Helper Functions =====

    #[test_only]
    /// Creates a TaskBoard and shares it (must be called from this module)
    public fun create_and_share_test_board(ctx: &mut TxContext) {
        let board = TaskBoard {
            id: object::new(ctx),
            total_tasks_created: 0,
            total_tasks_completed: 0,
        };
        transfer::share_object(board);
    }

    #[test_only]
    /// Creates an AdminCap for testing purposes
    public fun create_test_admin_cap(ctx: &mut TxContext): AdminCap {
        AdminCap {
            id: object::new(ctx),
        }
    }

    #[test_only]
    /// Destroys an AdminCap after testing
    public fun destroy_test_admin_cap(cap: AdminCap) {
        let AdminCap { id } = cap;
        object::delete(id);
    }
}
