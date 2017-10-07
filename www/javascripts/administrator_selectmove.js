
JSAN.use('DOM.Events', 'addListener');
addListener(window, 'load',
    function (e)
    {
        document.forms[0].onsubmit = function ()
        {
            var boxes = new Array('v', 'i');
            for (i = 0; i < boxes.length; i++)
            {
                var box     = eval('document.forms[0].' + boxes[i]);
                var options = box.getElementsByTagName('OPTION');
                for (n = 0; n < options.length; n++)
                {
                    options[n].selected = true;
                }
            }
        }
    }
);

function remove1()
{
    swap(document.forms[0].v, document.forms[0].i);
}

function add()
{
    swap(document.forms[0].i, document.forms[0].v);
}

function swap(from, to)
{
    var i, j, optGroups, options;
    optGroups = from.getElementsByTagName("OPTGROUP");
    for (i = 0; i < optGroups.length; i++)
    {
        options = optGroups[i].getElementsByTagName("OPTION");
        removeArray = [];
        for (j = 0; j < options.length; j++)
        {
            if (options[j].selected == true)
            {
                text = options[j].textContent ? options[j].textContent : options[j].innerText;
                addBox(to,   optGroups[i].label, options[j].value, text);
                removeArray.push(options[j].value);
            }
        }
        for (j = 0; j < removeArray.length; j++)
        {
            delBox(from, removeArray[j]);
        }
    }
    wipeExtraOptGroups(from);
}

function addBox(whichBox, optGroup, key, value)
{
    var optGroups, i, options;
    found = -1;
    optGroups = whichBox.getElementsByTagName('OPTGROUP');
    for (i = 0; i < optGroups.length; i++)
    {
        if (optGroups[i].label == optGroup)
            found = i;
    }
    newOption = document.createElement('OPTION');
    newOption.value       = key;
    newOption.innerText   = value;
    newOption.textContent = value;
    if (found == -1)
    {
        newOptGroup = document.createElement('OPTGROUP');
        newOptGroup.label = optGroup;
        whichBox.appendChild(newOptGroup);
        newOptGroup.appendChild(newOption);
    }
    else
    {
        optGroups[found].appendChild(newOption);
    }
}

function delBox(whichBox, key)
{
    var i;
    for (i = 0; i < whichBox.options.length; i++)
    {
        if (whichBox.options[i].value == key)
        {
            whichBox.options[i] = null;
        }
    }
}

function wipeExtraOptGroups(whichBox)
{
    var i, optGroups, options;
    optGroups = whichBox.getElementsByTagName('OPTGROUP');
    for (i = 0; i < optGroups.length; i++)
    {
        options = optGroups[i].getElementsByTagName('OPTION');
        if (options.length == 0)
        {
            whichBox.removeChild(optGroups[i]);
        }
    }
}
