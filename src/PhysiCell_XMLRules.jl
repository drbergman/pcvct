module PhysiCell_XMLRules

using LightXML, DataFrames, CSV

struct Behavior
    name::String
    response::Symbol
    max_response::String
    function Behavior(name::String, response::Symbol, max_response::String)
        if response != :increases && response != :decreases
            throw("The response must be either :increases or :decreases. Got $response.")
        end
        new(name, response, max_response)
    end
end

Behavior(name::String, response::String, max_response::String) = Behavior(name, Symbol(response), max_response)
Behavior(name::String, response::String) = Behavior(name, Symbol(response), "")
Behavior(name, response, max_response::Float64) = Behavior(name, response, string(max_response))

struct Signal
    name::String
    half_max::String
    hill_power::String
    applies_to_dead::String
end

function Signal(name::String, half_max::Float64, hill_power::T where {T<:Real}, applies_to_dead::Bool)
    return Signal(name, string(half_max), string(hill_power), applies_to_dead ? "1" : "0" )
end

struct Rule
    cell_type::String
    behavior::Behavior
    signal::Signal
end

function getElement(parent_element::XMLElement, element_name::String; require_exist::Bool=false)
    ce = find_element(parent_element, element_name)
    if isnothing(ce) && require_exist
        throw("Element '$element_name' not found in parent element '$parent_element'")
    end
    return ce
end

function createElement(parent_element::XMLElement, element_name::String; require_new::Bool=true)
    if require_new && !isnothing(getElement(parent_element, element_name; require_exist=false))
        throw("Element '$element_name' already exists in parent element '$parent_element'")
    end
    return new_child(parent_element, element_name)
end

function getOrCreateElement(parent_element::XMLElement, element_name::String)
    ce = getElement(parent_element, element_name; require_exist=false)
    if isnothing(ce)
        ce = createElement(parent_element, element_name; require_new=false) # since we already checked it doesn't exist, don't need it to be new
    end
    return ce
end

function getElementByAttribute(parent_element::XMLElement, element_name::String, attribute_name::String, attribute_value::String; require_exist::Bool=false)
    candidate_elements = get_elements_by_tagname(parent_element, element_name)
    for ce in candidate_elements
        if attribute(ce,attribute_name)==attribute_value
            return ce
        end
    end
    if require_exist
        throw("Element '$element_name' not found in parent element '$parent_element' with attribute '$attribute_name' = '$attribute_value'")
    end
    return nothing
end

function createElementByAttribute(parent_element::XMLElement, element_name::String, attribute_name::String, attribute_value::String; require_new::Bool=true)
    if require_new && !isnothing(getElementByAttribute(parent_element, element_name, attribute_name, attribute_value; require_exist=false))
        throw("$(element_name) already exists with (attribute, value) = ($(attribute_name), $(attribute_value)).") # improve this to name the parent element and the new element name
    end
    ce = new_child(parent_element, element_name)
    set_attribute(ce, attribute_name, attribute_value)
    return ce
end

function getOrCreateElementByAttribute(parent_element::XMLElement, element_name::String, attribute_name::String, attribute_value::String)
    ce = getElementByAttribute(parent_element, element_name, attribute_name, attribute_value; require_exist=false)
    if isnothing(ce)
        ce = createElementByAttribute(parent_element, element_name, attribute_name, attribute_value; require_new=false) # since we already checked it doesn't exist, don't need it to be new
    end
    return ce
end

function getResponse(xml_root::XMLElement, cell_type::String, behavior::Behavior) # this could be called "getOrCreateResponse", but I don't think it will ever be needed to either only get or only create it
    response_signals = (behavior.response == :decreases) ? "decreasing_signals" : "increasing_signals"
    cell_type_element = getOrCreateElementByAttribute(xml_root, "cell_definition", "name", cell_type)
    behavior_element = getOrCreateElementByAttribute(cell_type_element, "behavior", "name", behavior.name)
    return getOrCreateElement(behavior_element, response_signals)
end

function addSignal(response_element::XMLElement, signal::Signal)
    signal_element = createElementByAttribute(response_element, "signal", "name", signal.name; require_new=true)
    setSignalParameters(signal_element, signal)
    return signal_element
end

function updateSignal(response_element::XMLElement, signal::Signal; require_exist::Bool=true)
    signal_element = getElementByAttribute(response_element, "signal", "name", signal.name; require_exist=require_exist)
    setSignalParameters(signal_element, signal)
    return signal_element
end

function setSignalParameters(signal_element::XMLElement, signal::Signal)
    half_max_element = getOrCreateElement(signal_element, "half_max")
    set_content(half_max_element, signal.half_max)
    hill_power_element = getOrCreateElement(signal_element, "hill_power")
    set_content(hill_power_element, signal.hill_power)
    applies_to_dead_element = getOrCreateElement(signal_element, "applies_to_dead")
    set_content(applies_to_dead_element, signal.applies_to_dead)
end

function addRule(xml_root::XMLElement, rule::Rule; require_max_response_unchanged::Bool=true)
    cell_type = rule.cell_type
    behavior = rule.behavior
    signal = rule.signal
    response_element = getResponse(xml_root, cell_type, behavior)

    max_response_element = getOrCreateElement(response_element, "max_response")
    max_response = content(max_response_element)
    if isempty(max_response)
        set_content(max_response_element, rule.behavior.max_response)
    else
        previous_max_response = parse(Float64, max_response)
        if previous_max_response == rule.behavior.max_response
        elseif require_max_response_unchanged
            throw("In adding the new rule, the max_response is being changed")
        else
            set_content(max_response_element, rule.behavior.max_response)
        end
    end
    addSignal(response_element, signal)
end

function updateRule(xml_root::XMLElement, rule::Rule)
    cell_type = rule.cell_type
    behavior = rule.behavior
    signal = rule.signal
    response_element = getResponse(xml_root, cell_type, behavior)
    max_response_element = getElement(response_element, "max_response"; require_exist=true)
    set_content(max_response_element, rule.behavior.max_response)
    updateSignal(response_element, signal; require_exist=true)
end

function addOrUpdateRule(xml_root::XMLElement, rule::Rule)
    cell_type = rule.cell_type
    behavior = rule.behavior
    signal = rule.signal
    response_element = getResponse(xml_root, cell_type, behavior)
    max_response_element = getElement(response_element, "max_response"; require_exist=false)
    set_content(max_response_element, rule.behavior.max_response)
    updateSignal(response_element, signal; require_exist=false)
end

function addRules(xml_root::XMLElement, data_frame::DataFrame)
    for row in eachrow(data_frame)
        cell_type = row[:cell_type]
        signal_name = row[:signal]
        response = row[:response]
        behavior_name = row[:behavior]
        max_response = row[:max_response]
        half_max = row[:half_max]
        hill_power = row[:hill_power]
        applies_to_dead = row[:applies_to_dead]
        behavior = Behavior(behavior_name, response, max_response)
        signal = Signal(signal_name, half_max, hill_power, applies_to_dead)
        rule = Rule(cell_type, behavior, signal)
        addRule(xml_root, rule)
    end
end

function addRules(xml_root::XMLElement, path_to_csv::String)
    df = CSV.read(path_to_csv, DataFrame; header=false, types=String)
    # set column names of df by vector
    rename!(df, [:cell_type, :signal, :response, :behavior, :max_response, :half_max, :hill_power, :applies_to_dead])
    return addRules(xml_root, df)
end

function writeRules(xml_doc::XMLDocument, path_to_csv::String)
    xml_root = create_root(xml_doc, "hypothesis_rulesets")
    addRules(xml_root, path_to_csv)
    return xml_doc
end

function writeRules(path_to_xml::String, path_to_csv::String)
    xml_doc = XMLDocument()
    writeRules(xml_doc, path_to_csv)
    save_file(xml_doc, path_to_xml)
    return
end

end