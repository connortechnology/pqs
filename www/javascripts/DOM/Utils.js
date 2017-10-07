/*
=head1 NAME
DOM.Utils
=head1 DESCRIPTION
This provides a group of useful functions for use within the DOM.
=head1 DEPENDENCIES
This requires JSAN to be installed.
=cut
*/
/*
try {
    // If a jsan variable has already been defined, use that, as in the case of tests.
    if ( typeof jsan != 'undefined' )
        jsan = new JSAN();
} catch (e) {
    throw "DOM.Utils requires JSAN to be loaded";
}
*/
if ( typeof DOM == 'undefined' )
    DOM = {};
/*
=head1 FUNCTIONS
These are functions that are exported to the JSAN.use()er's namespace.
=head2 $()
This function will attempt, if given a string, to find an element in the DOM that corresponds to that string. If given anything else, it will return that back.
It will attempt to call the following methods, in order:
=over 4
=item * document.getElementById( arg )
=item * document.getElementsByName( arg )[0]
=item * document.getElementsByClass( arg )[0]
=item * document.getElementsByTag( arg )[0]
=back
In the case where a method returns back a collection, the first one from that collection will be chosen.
  function someFunction ( element, ... ) {
      // Guarantee that element is actually an element object
      element = $(element);
      ...
  }
=cut
*/
DOM.Utils = {
    EXPORT: [ '$' ]
   ,'$' : function () {
        var elements = new Array();
        for (var i = 0; i < arguments.length; i++) {
            var element = arguments[i];
            if (typeof element == 'string')
                element = document.getElementById(element)
                    || document.getElementsByName(element)[0]
                    || document.getElementsByClass(element)[0]
                    || document.getElementsByTagName(element)[0]
                    || undefined
                ;
            if (arguments.length == 1)
                return element;
            elements.push( element );
        }
        return elements;
    }
};
/*
=head1 ADDITIONS TO document
=head2 getElementsByClass()
This method acts as getElementsByName(), but checks against the classes vs. the name.
getElementsByClassName() is an alias that is provided for Prototype API compatibility.
=cut
*/
document.getElementsByClass = function(className) {
    var children = document.getElementsByTagName('*') || document.all;
    var elements = new Array();

    for (var i = 0; i < children.length; i++) {
        var child = children[i];
        var classNames = child.className.split(' ');
        for (var j = 0; j < classNames.length; j++) {
            if (classNames[j] == className) {
              elements.push(child);
              break;
            }
        }
    }

    return elements;
};
document.getElementsByClassName = document.getElementsByClass;
/*
=head1 SUPPORT
Currently, there is no mailing list or IRC channel. Please send bug reports and patches to the author.
=head1 AUTHOR
Rob Kinyon (rob.kinyon@iinteractive.com)
Originally written by Sam Stephenson (sam@conio.net)
My time is generously donated by Infinity Interactive, Inc. L<http://www.iinteractive.com>
=cut
*/
