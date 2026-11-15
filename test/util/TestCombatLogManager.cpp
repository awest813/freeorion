#include <boost/test/unit_test.hpp>

#include "combat/CombatLogManager.h"

BOOST_AUTO_TEST_SUITE(TestCombatLogManager);

BOOST_AUTO_TEST_CASE(LogIdsStartAtOne) {
    CombatLogManager manager;
    BOOST_CHECK_EQUAL(manager.LatestLogID(), 0);
    BOOST_CHECK_EQUAL(manager.AddNewLog(CombatLog{}), 1);
    BOOST_CHECK(manager.GetLog(1));
}

// A client clears its logs when a game starts or is loaded, then learns the
// latest id from the server and fetches the logs it doesn't have. A cleared
// manager must look like a new one, or it would wait for a log 0 forever.
BOOST_AUTO_TEST_CASE(ClearedManagerIsLikeANewOne) {
    CombatLogManager manager;
    manager.AddNewLog(CombatLog{});
    manager.AddNewLog(CombatLog{});
    manager.Clear();
    BOOST_CHECK_EQUAL(manager.LatestLogID(), 0);
    BOOST_CHECK(manager.IncompleteLogIDs().empty());
    BOOST_CHECK_EQUAL(manager.AddNewLog(CombatLog{}), 1);
}

// Completing a log beyond the latest known id marks the ones in between as
// incomplete, starting after the latest; with nothing known, from id 1.
BOOST_AUTO_TEST_CASE(CompletingAheadRequestsTheGap) {
    CombatLogManager manager;
    manager.Clear();
    manager.CompleteLog(3, CombatLog{});
    const auto incomplete = manager.IncompleteLogIDs();
    BOOST_CHECK_EQUAL(incomplete.size(), 2u);
    BOOST_CHECK_EQUAL(incomplete.front(), 1);
    BOOST_CHECK(manager.GetLog(3));
}

BOOST_AUTO_TEST_SUITE_END();
