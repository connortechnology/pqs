// Setup the tabs and initial state for any "product selector" items.
Event.observe(window, 'load', function (e) {
    var items = $$('div.product');

    for (var i = 0, len = items.length; i < len; i++) {
        // Create the tabs for questions/matrix view switching
        create_tabs(items[i]);

        var form = items[i].down('form');

        // Check the form for completeness on submission.
        form.observe('submit', check_submit);

        // Maintain answer integrity.
        form.getElements().each(function (elem) {
            if (!elem.name) return;

            if (elem.name.match(/^q\d+$/))
                elem.observe('click', question_change);
            else if (elem.name == 'pid')
                elem.observe('click', select_project);
        });

        var selected = get_selected(form);
        restrict_answers(form, selected);

     }

});

// Create the question/matrix view tab bar for a "product selector" item.
function create_tabs (item) {
    // Create the tabs.
    var tabs = new Element('div', { 'class' : 'tabs' });

    var tab_q = new Element('span').update('Questions');
    var tab_m = new Element('span').update('Matrix');

    tabs.appendChild(tab_q);
    tabs.appendChild(tab_m);

    var views = item.down('form.info > div.views');
    views.insertBefore(tabs, views.firstChild);

    // Bind them to the item views.
    var questions = item.down('.questions');
    var matrix    = item.down('.matrix');

    tab_q.observe('click', function () {
            tab_q.addClassName('selected');
            tab_m.removeClassName('selected');
            questions.show();
            matrix.hide();
    });

    tab_m.observe('click', function () {
            tab_q.removeClassName('selected');
            tab_m.addClassName('selected');
            questions.hide();
            matrix.show();
    });

    // Set initial state.
    if (questions.hasClassName('selected')) {
        matrix.hide();
        tab_q.addClassName('selected');
    }
    else {
        questions.hide();
        tab_m.addClassName('selected');
    }

    return item;
}

// Check that either the project is selected from the matrix or the user has
// answered all the questions.
function check_submit (e) {
    var form = e.element();

    // If a project is selected in the matrix that's enough.
    if ( form.getInputs('radio', 'pid').any(is_checked) )
        return true;

    // Otherwise make sure each question has been answered. Note: We only need to
    // check radios as selects work properly (some option always selected).
    var has_answer = new Hash;
    form.getInputs('radio').each(function (elem) {
        if ((! elem.name.match(/^q\d+$/)) || has_answer.get(elem.name)) return;

        has_answer.set(elem.name, elem.checked);
    });

    // If they haven't been, alert the user and don't proceed further.
    if (! has_answer.values().all()) {
        e.stop();
        alert('Please select a product from the matrix or answer all the questions.');
        return false;
    }

    return true;
}

function is_checked (elem) { return elem.checked }


// Selects the first answer of each question for browsers that don't treat
// radio buttons as always having some value.
function set_initial_answers (item) {
   var seen = new Hash;

    item.down('form').getInputs('radio').each(function (elem) {
        if ((! elem.name.match(/^q\d+$/)) || seen.get(elem.name)) return;

        seen.set(elem.name, true);

        elem.checked = true;
    });

    return true;
}

function question_change (e) {
    var form     = e.element().form;
    var selected = get_selected(form);

    // Disable any invalid inputs (answers).
    restrict_answers(form, selected);

    // If all questions are answered, mirror the selection in the matrix.
    if (selected.compact().length == selected.length) {
        if (!form.mappings)
            form.mappings = build_set(form);

        var project = find_project(selected, form.mappings);

        $('set' + project.value.join('-')).checked = true;
    }

    return true;
}

function select_project (e) {
    var input = e.element();
    var form  = input.form;

    var selected = input.id.substr(3).split('-');

    // Lookup the project number and check the answers that specify it.
    selected.each(function (answer) {
        var elem = $('a' + answer);
        if   (elem.type == 'option') elem.selected = true 
        else                         elem.checked = true;
    });

    // Disable any invalid inputs (answers).
    restrict_answers(form, selected);

    return true;
}


// Generate the project <-> answer set mappings for the item.
function build_set (form) {

    var mapping = new Hash;
    form.getInputs('radio', 'pid').each(function (elem) {
        mapping.set(elem.value, elem.id.substr(3).split('-'));
    });

    return mapping;
}

// Given answers and all solutions, find the project that corresponds.
function find_project(selected, solutions) {

    var search = selected.join('-');

    var project = solutions.find(function (pair) {
        return pair.value.join('-') == search;
    });

    return project;
}

function product_answers (root) {
    return root.descendants().map(function (elem) {
        return (elem.id.match(/^a\d+$/) ? elem : undefined)
    }).compact();
}

// Get the selected answers to the questions in document order.
function get_selected (form) {

    if (!form.answers)
        form.answers = product_answers(form);

    var questions = new Array;
    var answer    = new Hash;

    form.answers.each(function (elem) {
        var key = (elem.parentNode.type == 'select-one' ? elem.up('select').name : elem.name);

        if (! answer.exists(key) ) {
            answer.set(key, undefined);
            questions.push(key);
        }
       
        // Set the answer to the question.
        //if (elem.type == 'option') {
        if (elem.parentNode.type == 'select-one' && elem.selected) {
            //answer.set(key, $F(elem));
            answer.set(key, elem.value);
        }
        else {
            if (elem.checked) {
                answer.set(key, $F(elem));
            }
        }
    });

    // Return the answers in the document order of the questions
    return questions.map(function (name) { return answer.get(name) });
}

// Given a set of selected answers, restrict the inputs that aren't valid.
function restrict_answers (form, selected) {

    if (!form.mappings)
        form.mappings = build_set(form);

    // Get a lookup of all invalid answers from this location.
    var answers = valid_moves(selected, form.mappings.values());

    var valid = new Hash;
    answers.flatten().compact().each(function (id) {
        valid.set('a' + id, true);
    });

    // (Dis|En)able the elemets
    if (!form.answers)
        form.answers = product_answers(form);

    form.answers.each(
        function (elem) {
            if   (valid.get(elem.id)) 
                elem.disabled = false;
            else
                elem.disabled = false;
                //elem.disabled = true;
            
        }
    );
}

// Given an answer set, find all valid steps from it (including itself).
function valid_moves (search, solutions) {

    var is_partial = !search.all();
  
    if (is_partial) {
        return partial_matches(search, solutions);
    }
    else
        return collapse_sets(find_matches(search, solutions));
}

// Given a search with unknown terms, find all possible steps from it. NOTE:
// This is not exactly 'snappy' code. The entire algorithm could bear a
// rethink or at least some refactoring of this.
function partial_matches (search, solutions) {

    var undefs = new Array;
    for (var i = 0; i < search.length; i++)
        if (search[i]) undefs.push(i);

    // Find every solution that contains us. This gives us all valid options
    // for the unanswered questions (undefined terms).
    var first = find_matches(search, solutions);

    // Reverse the search and find the valid steps for the current terms.
    var second = new Array;
    first.each(function (set) {
        set = set.clone();

        // Reverse the unknown questions.
        undefs.each(function (j) { set[j] = undefined }); 

        find_matches(set, solutions).each(function (a) { second.push(a)});
    });

    // Collapse both sets and combine the known and unknown terms.
    first  = collapse_sets(second);
    second = collapse_sets(second);

    var possible = new Array;
    for (var i = 0; i < search.length; i++)
        possible[i] = search[i] ? first[i] : second[i];

    return possible;
}

// Find all solutions that are a single step from the search.
function find_matches (search, solutions) {
    var defined = search.all() ? search.length - 1 : search.compact().length; 

    return solutions.findAll(function (solution) {
        var matches = solution.zip(search, function (a) { return a[1] ? a[0] == a[1] : false });

        return matches.grep(/true/).length >= defined;
    });
}

// Flatten a list of solutions into possible answers per question.
function collapse_sets (solutions) {
    var collapsed = new Array;

    solutions.each(function (solution) {
        for (var i = 0; i < solution.length; i++) {
            if (!collapsed[i]) collapsed[i] = new Hash;

            collapsed[i].set(solution[i], true);
        }
    });

    return collapsed.map(function (a) { return a.keys() });
}


// Checks if a key exists in a hash.
Hash.addMethods({
	exists: function(key) { return key in this._object }
});

