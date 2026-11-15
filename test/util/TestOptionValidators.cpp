#include <boost/test/unit_test.hpp>

#include "util/OptionsDB.h"
#include "util/OptionValidators.h"
#include "util/XMLDoc.h"

BOOST_AUTO_TEST_SUITE(TestOptionValidators);

// Derived validators override only Validate(const std::string&); validating a
// std::string_view (as OptionsDB::Validate and Option::SetFromString do) must
// still apply their constraints.

// Called through ValidatorBase, as OptionsDB does: the derived classes hide
// the base string_view overload from direct calls.

BOOST_AUTO_TEST_CASE(RangedValidatorChecksStringView) {
    const RangedValidator<int> ranged(10, 20);
    const ValidatorBase& validator = ranged;
    BOOST_CHECK_NO_THROW(validator.Validate(std::string_view{"15"}));
    BOOST_CHECK_THROW(validator.Validate(std::string_view{"3"}), std::exception);
    BOOST_CHECK_THROW(validator.Validate(std::string_view{"21"}), std::exception);
}

BOOST_AUTO_TEST_CASE(DiscreteValidatorChecksStringView) {
    const DiscreteValidator<std::string> discrete(std::vector<std::string>{"auto", "manual"});
    const ValidatorBase& validator = discrete;
    BOOST_CHECK_NO_THROW(validator.Validate(std::string_view{"auto"}));
    BOOST_CHECK_THROW(validator.Validate(std::string_view{"other"}), std::exception);
}

BOOST_AUTO_TEST_CASE(OptionsDBValidateAppliesRange) {
    GetOptionsDB().Add<int>("test.validators.ranged", "TEST_RANGED", 15, RangedValidator<int>(10, 20));
    BOOST_CHECK_NO_THROW(GetOptionsDB().Validate("test.validators.ranged", "12"));
    BOOST_CHECK_THROW(GetOptionsDB().Validate("test.validators.ranged", "3"), std::exception);
}

BOOST_AUTO_TEST_CASE(OutOfRangeConfigValueIsIgnored) {
    GetOptionsDB().Add<int>("test.validators.config", "TEST_CONFIG", 15, RangedValidator<int>(10, 20));

    XMLDoc doc;
    XMLElement test_elem{"test"};
    XMLElement validators_elem{"validators"};
    XMLElement config_elem{"config", std::string{"3"}};
    validators_elem.AddChild(std::move(config_elem));
    test_elem.AddChild(std::move(validators_elem));
    doc.root_node.AddChild(std::move(test_elem));

    GetOptionsDB().SetFromXML(doc); // logs and keeps the old value
    BOOST_CHECK_EQUAL(GetOptionsDB().Get<int>("test.validators.config"), 15);
}

BOOST_AUTO_TEST_SUITE_END();
