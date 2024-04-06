using LightXML

xml_doc = XMLDocument()
xroot = create_root(xml_doc, "hypothesis_rulesets")

cell_types = ["default","tumor","cd8"]

function getElementByAttribute(current_element, element_name, attribute_name, attribute_value)
    candidate_elements = get_elements_by_tagname(current_element, element_name)
    for ce in candidate_elements
        if attribute(ce,attribute_name)==attribute_value
            return ce
        end
    end
    return nothing
end

function createElementByAttribute(current_element, element_name, attribute_name, attribute_value; unique=false)
    if unique && !isnothing(getElementByAttribute(current_element, element_name, attribute_name, attribute_value))
        throw("Element already exists")
    end
    current_element = new_child(current_element, element_name)
    set_attribute(current_element, attribute_name, attribute_value)
    return current_element
end

getHypothesisRuleset(xroot, cell_type) = createOrGetElementByAttribute(xroot, "hypothesis_ruleset", "name", cell_type)
getBehavior(current_element, behavior) = createOrGetElementByAttribute(current_element, "behavior", "name", behavior)
getSignal(current_element, signal) = getElementByAttribute(current_element, "signal", "name", signal)

function getResponse(current_element, response)
    name = (response=="decreases") ? "decreasing_signals" : "increasing_signals"
    return createOrGetElement(current_element, name)
end

function createOrGetElementByAttribute(current_element, element_name, attribute_name, attribute_value)
    ce = getElementByAttribute(current_element, element_name, attribute_name, attribute_value)
    if isnothing(ce)
        ce = createElementByAttribute(current_element, element_name, attribute_name, attribute_value; unique=true)
    end
    return ce
end

function createOrGetElement(current_element, name)
    ce = find_element(current_element, name)
    if isnothing(ce)
        ce = new_child(current_element, name)
    end
    return ce
end

function createMaxResponse(current_element, max_response)
    ce = createOrGetElement(current_element, "max_response")
    current_content = content(ce)
    if isempty(current_content)
        return add_text(ce, string(max_response))
    end
    if max_response == parse(Float64, current_content)
        return # no need to overwrite
    end
    throw("The max response value is different than previously set. Make sure all the max response values within this response element are identical.")
end

function setSignalParameters(signal_element, half_max, hill_power, applies_to_dead)
    child = createOrGetElement(signal_element, "half_max")
    set_content(child, string(half_max))
    child = createOrGetElement(signal_element, "hill_power")
    set_content(child, string(hill_power))
    child = createOrGetElement(signal_element, "applies_to_dead")
    set_content(child, string(applies_to_dead))
    return
end

function createNewSignal(current_element, signal_name, half_max, hill_power, applies_to_dead)
    signal_element = createElementByAttribute(current_element, "signal", "name", signal_name; unique=true)
    setSignalParameters(signal_element, half_max, hill_power, applies_to_dead)
end

function updateSignal(current_element, signal_name, half_max, hill_power, applies_to_dead)
    signal_element = getSignal(current_element, signal_name)
    if isnothing(signal_element)
        return createNewSignal(current_element, signal_name, half_max, hill_power, applies_to_dead)
    end
    setSignalParameters(signal_element, half_max, hill_power, applies_to_dead)
    return
end

function getResponseElement(xroot, cell_type, behavior, response)
    current_element = getHypothesisRuleset(xroot, cell_type)
    current_element = getBehavior(current_element, behavior)
    current_element = getResponse(current_element, response)
    return current_element
end

function addRule(xroot, rule)
    response_element = getResponseElement(xroot, rule[[1,4,3]]...)
    max_response = rule[5]
    createMaxResponse(response_element, max_response);
    createNewSignal(response_element, rule[2], rule[6:8]...);
    return
end

function updateRule(xroot, rule)
    response_element = getResponseElement(xroot, rule[[1,4,3]]...)
    max_response = rule[5]
    createMaxResponse(response_element, max_response);
    updateSignal(response_element, rule[[2,6,7,8]]...);
    signal_element = getSignal(response_element, rule[2]);
    setSignalParameters(signal_element, rule[6:8]...);
    return
end

rule = ["default","oxygen","increases","cycle entry",1e-3,10,2,0]

addRule(xroot, rule)

print("added one rule")

rule2 = ["default","oxygen","increases","cycle entry",1e-3,8,2,0];
updateRule(xroot, rule2);

rule3 = ["tumor","substrate","decreases","migration bias",1e-3,10,2,0];
addRule(xroot, rule3);

rule4 = ["cd8","pressure","decreases","cycle entry",1e-3,10,2,0];
addRule(xroot, rule4);

for cell_type in cell_types
    rule = [cell_type,"oxygen","increases","cool dancing",1e-3,10,2,0]
    addRule(xroot, rule)
end

save_file(xml_doc, "test.xml")
