#[test_only]
module task_management_system::task_management_tests {

    use std::string;
    use sui::test_scenario as ts;
    use task_management_system::task_management::{
        Self,
        Task, UserProfile, TaskBoard, AdminCap,
    };

    // ===== Test Addresses =====
    const ADMIN: address = @0xAD;
    const USER1: address = @0xA1;
    const USER2: address = @0xA2;

    // ===== Helper Functions =====

    #[test_only]
    /// Sets up a basic test environment: creates a board, admin cap, and a profile for USER1
    fun setup_test(): ts::Scenario {
        let mut scenario = ts::begin(ADMIN);
        // Create task board and admin cap
        {
            let ctx = ts::ctx(&mut scenario);
            task_management::create_and_share_test_board(ctx);

            let admin_cap = task_management::create_test_admin_cap(ctx);
            transfer::public_transfer(admin_cap, ADMIN);
        };
        scenario
    }

    // ===== Test 1: Create Profile Successfully =====
    #[test]
    fun test_create_profile() {
        let mut scenario = setup_test();

        // USER1 creates a profile
        ts::next_tx(&mut scenario, USER1);
        {
            task_management::create_profile(ts::ctx(&mut scenario));
        };

        // Verify profile fields
        ts::next_tx(&mut scenario, USER1);
        {
            let profile = ts::take_from_sender<UserProfile>(&scenario);

            assert!(task_management::get_profile_owner(&profile) == USER1);
            assert!(task_management::get_profile_tasks_completed(&profile) == 0);
            assert!(task_management::get_profile_points(&profile) == 0);
            assert!(task_management::get_profile_level(&profile) == 1);

            ts::return_to_sender(&scenario, profile);
        };

        ts::end(scenario);
    }

    // ===== Test 2: Create Task Successfully =====
    #[test]
    fun test_create_task() {
        let mut scenario = setup_test();

        // ADMIN creates a task
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);

            task_management::create_task(
                &mut board,
                string::utf8(b"Build Frontend"),
                string::utf8(b"Create a React app for the project"),
                50,
                ts::ctx(&mut scenario),
            );

            assert!(task_management::get_board_total_created(&board) == 1);

            ts::return_shared(board);
        };

        // Verify task was created with correct fields
        ts::next_tx(&mut scenario, ADMIN);
        {
            let task = ts::take_from_sender<Task>(&scenario);

            assert!(task_management::get_task_title(&task) == string::utf8(b"Build Frontend"));
            assert!(task_management::get_task_description(&task) == string::utf8(b"Create a React app for the project"));
            assert!(task_management::get_task_reward_points(&task) == 50);
            assert!(task_management::get_task_status(&task) == 0); // STATUS_PENDING
            assert!(task_management::get_task_creator(&task) == ADMIN);
            assert!(!task_management::is_task_completed(&task));
            assert!(!task_management::is_task_assigned(&task));

            ts::return_to_sender(&scenario, task);
        };

        ts::end(scenario);
    }

    // ===== Test 3: Assign Task Successfully =====
    #[test]
    fun test_assign_task() {
        let mut scenario = setup_test();

        // Create a task
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            task_management::create_task(
                &mut board,
                string::utf8(b"Write Tests"),
                string::utf8(b"Unit tests for the module"),
                75,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(board);
        };

        // Assign task to USER1
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            task_management::assign_task(&mut task, USER1, ts::ctx(&mut scenario));

            assert!(task_management::is_task_assigned(&task));
            assert!(*task_management::get_task_assignee(&task).borrow() == USER1);

            ts::return_to_sender(&scenario, task);
        };

        ts::end(scenario);
    }

    // ===== Test 4: Complete Task and Earn Points =====
    #[test]
    fun test_complete_task_and_earn_points() {
        let mut scenario = setup_test();

        // Create task as ADMIN
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            task_management::create_task(
                &mut board,
                string::utf8(b"Deploy Contract"),
                string::utf8(b"Deploy to testnet"),
                50,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(board);
        };

        // Assign task to USER1
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            task_management::assign_task(&mut task, USER1, ts::ctx(&mut scenario));
            // Transfer task to USER1 so they can interact with it
            transfer::public_transfer(task, USER1);
        };

        // USER1 creates a profile
        ts::next_tx(&mut scenario, USER1);
        {
            task_management::create_profile(ts::ctx(&mut scenario));
        };

        // USER1 completes the task
        ts::next_tx(&mut scenario, USER1);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);

            task_management::complete_task(
                &mut task,
                &mut board,
                &mut profile,
                ts::ctx(&mut scenario),
            );

            // Verify task is completed
            assert!(task_management::is_task_completed(&task));
            assert!(task_management::get_task_status(&task) == 1);

            // Verify profile updated
            assert!(task_management::get_profile_tasks_completed(&profile) == 1);
            assert!(task_management::get_profile_points(&profile) == 50);

            // Verify board stats
            assert!(task_management::get_board_total_completed(&board) == 1);

            ts::return_to_sender(&scenario, task);
            ts::return_to_sender(&scenario, profile);
            ts::return_shared(board);
        };

        ts::end(scenario);
    }

    // ===== Test 5: Level Up on Point Threshold =====
    #[test]
    fun test_level_up() {
        let mut scenario = setup_test();

        // Create a task worth 100 points (enough for level 2)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            task_management::create_task(
                &mut board,
                string::utf8(b"Big Task"),
                string::utf8(b"A high-reward task"),
                100,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(board);
        };

        // Assign to USER1 and transfer
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            task_management::assign_task(&mut task, USER1, ts::ctx(&mut scenario));
            transfer::public_transfer(task, USER1);
        };

        // USER1 creates profile
        ts::next_tx(&mut scenario, USER1);
        {
            task_management::create_profile(ts::ctx(&mut scenario));
        };

        // USER1 completes the task -> should level up to 2
        ts::next_tx(&mut scenario, USER1);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);

            task_management::complete_task(
                &mut task,
                &mut board,
                &mut profile,
                ts::ctx(&mut scenario),
            );

            assert!(task_management::get_profile_level(&profile) == 2);
            assert!(task_management::get_profile_points(&profile) == 100);

            ts::return_to_sender(&scenario, task);
            ts::return_to_sender(&scenario, profile);
            ts::return_shared(board);
        };

        ts::end(scenario);
    }

    // ===== Test 6: Admin Reassign Task =====
    #[test]
    fun test_admin_reassign_task() {
        let mut scenario = setup_test();

        // Create and assign a task
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            task_management::create_task(
                &mut board,
                string::utf8(b"Review Code"),
                string::utf8(b"Code review for PR #42"),
                30,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(board);
        };

        // Assign to USER1
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            task_management::assign_task(&mut task, USER1, ts::ctx(&mut scenario));

            assert!(*task_management::get_task_assignee(&task).borrow() == USER1);

            // Admin reassigns to USER2
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            task_management::admin_reassign_task(&admin_cap, &mut task, USER2);

            assert!(*task_management::get_task_assignee(&task).borrow() == USER2);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_to_sender(&scenario, task);
        };

        ts::end(scenario);
    }

    // ===== Test 7: Fail - Create Task with Empty Title =====
    #[test]
    #[expected_failure(abort_code = task_management::EEmptyTitle)]
    fun test_fail_create_task_empty_title() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            task_management::create_task(
                &mut board,
                string::utf8(b""), // empty title
                string::utf8(b"Some description"),
                50,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(board);
        };

        ts::end(scenario);
    }

    // ===== Test 8: Fail - Create Task with Zero Reward Points =====
    #[test]
    #[expected_failure(abort_code = task_management::EInvalidRewardPoints)]
    fun test_fail_create_task_zero_points() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            task_management::create_task(
                &mut board,
                string::utf8(b"No Reward Task"),
                string::utf8(b"This has zero points"),
                0, // zero reward
                ts::ctx(&mut scenario),
            );
            ts::return_shared(board);
        };

        ts::end(scenario);
    }

    // ===== Test 9: Fail - Complete Already Completed Task =====
    #[test]
    #[expected_failure(abort_code = task_management::ETaskAlreadyCompleted)]
    fun test_fail_complete_already_completed() {
        let mut scenario = setup_test();

        // Create task
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            task_management::create_task(
                &mut board,
                string::utf8(b"One-time Task"),
                string::utf8(b"Can only complete once"),
                25,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(board);
        };

        // Assign and transfer to USER1
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            task_management::assign_task(&mut task, USER1, ts::ctx(&mut scenario));
            transfer::public_transfer(task, USER1);
        };

        // USER1 creates profile
        ts::next_tx(&mut scenario, USER1);
        {
            task_management::create_profile(ts::ctx(&mut scenario));
        };

        // First completion - should succeed
        ts::next_tx(&mut scenario, USER1);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);

            task_management::complete_task(&mut task, &mut board, &mut profile, ts::ctx(&mut scenario));

            ts::return_to_sender(&scenario, task);
            ts::return_to_sender(&scenario, profile);
            ts::return_shared(board);
        };

        // Second completion - should fail
        ts::next_tx(&mut scenario, USER1);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);

            task_management::complete_task(&mut task, &mut board, &mut profile, ts::ctx(&mut scenario));

            ts::return_to_sender(&scenario, task);
            ts::return_to_sender(&scenario, profile);
            ts::return_shared(board);
        };

        ts::end(scenario);
    }

    // ===== Test 10: Fail - Complete Unassigned Task =====
    #[test]
    #[expected_failure(abort_code = task_management::ETaskNotAssigned)]
    fun test_fail_complete_unassigned_task() {
        let mut scenario = setup_test();

        // Create task (not assigned)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            task_management::create_task(
                &mut board,
                string::utf8(b"Unassigned Task"),
                string::utf8(b"Nobody is assigned"),
                40,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(board);
        };

        // ADMIN creates profile
        ts::next_tx(&mut scenario, ADMIN);
        {
            task_management::create_profile(ts::ctx(&mut scenario));
        };

        // Try to complete without assigning
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);

            task_management::complete_task(&mut task, &mut board, &mut profile, ts::ctx(&mut scenario));

            ts::return_to_sender(&scenario, task);
            ts::return_to_sender(&scenario, profile);
            ts::return_shared(board);
        };

        ts::end(scenario);
    }

    // ===== Test 11: Fail - Assign Already Assigned Task =====
    #[test]
    #[expected_failure(abort_code = task_management::ETaskAlreadyAssigned)]
    fun test_fail_assign_already_assigned() {
        let mut scenario = setup_test();

        // Create task
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            task_management::create_task(
                &mut board,
                string::utf8(b"Assigned Task"),
                string::utf8(b"Already has assignee"),
                30,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(board);
        };

        // Assign to USER1
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            task_management::assign_task(&mut task, USER1, ts::ctx(&mut scenario));

            // Try to assign again - should fail
            task_management::assign_task(&mut task, USER2, ts::ctx(&mut scenario));

            ts::return_to_sender(&scenario, task);
        };

        ts::end(scenario);
    }

    // ===== Test 12: Fail - Non-Creator Assigns Task =====
    #[test]
    #[expected_failure(abort_code = task_management::ENotCreator)]
    fun test_fail_non_creator_assigns() {
        let mut scenario = setup_test();

        // ADMIN creates task
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);
            task_management::create_task(
                &mut board,
                string::utf8(b"Admin Task"),
                string::utf8(b"Created by admin"),
                60,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(board);
        };

        // Transfer task to USER1
        ts::next_tx(&mut scenario, ADMIN);
        {
            let task = ts::take_from_sender<Task>(&scenario);
            transfer::public_transfer(task, USER1);
        };

        // USER1 tries to assign (not the creator) - should fail
        ts::next_tx(&mut scenario, USER1);
        {
            let mut task = ts::take_from_sender<Task>(&scenario);
            task_management::assign_task(&mut task, USER2, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, task);
        };

        ts::end(scenario);
    }

    // ===== Test 13: Multiple Tasks and Board Stats =====
    #[test]
    fun test_board_stats_multiple_tasks() {
        let mut scenario = setup_test();

        // Create 3 tasks
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut board = ts::take_shared<TaskBoard>(&scenario);

            task_management::create_task(
                &mut board,
                string::utf8(b"Task 1"),
                string::utf8(b"First task"),
                10,
                ts::ctx(&mut scenario),
            );
            task_management::create_task(
                &mut board,
                string::utf8(b"Task 2"),
                string::utf8(b"Second task"),
                20,
                ts::ctx(&mut scenario),
            );
            task_management::create_task(
                &mut board,
                string::utf8(b"Task 3"),
                string::utf8(b"Third task"),
                30,
                ts::ctx(&mut scenario),
            );

            assert!(task_management::get_board_total_created(&board) == 3);
            assert!(task_management::get_board_total_completed(&board) == 0);

            ts::return_shared(board);
        };

        ts::end(scenario);
    }
}
