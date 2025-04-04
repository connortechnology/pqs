if(typeof Effect == 'undefined')
  throw("dragdrop.js requires including script.aculo.us' effects.js library");

var Stretchables = {
  drags: [],
  observers: [],

  register: function(draggable) {
    if(this.drags.length == 0) {
      this.eventMouseUp   = this.endStretch.bindAsEventListener(this);
      this.eventMouseMove = this.updateStretch.bindAsEventListener(this);
      this.eventKeypress  = this.keyPress.bindAsEventListener(this);

      Event.observe(document, "mouseup", this.eventMouseUp);
      Event.observe(document, "mousemove", this.eventMouseMove);
      Event.observe(document, "keypress", this.eventKeypress);
    }
    this.drags.push(draggable);
  },

  unregister: function(draggable) {
    this.drags = this.drags.reject(function(d) { return d==draggable });
    if(this.drags.length == 0) {
      Event.stopObserving(document, "mouseup", this.eventMouseUp);
      Event.stopObserving(document, "mousemove", this.eventMouseMove);
      Event.stopObserving(document, "keypress", this.eventKeypress);
    }
  },

  activate: function(draggable) {
    if(draggable.options.delay) {
      this._timeout = setTimeout(function() {
        Stretchables._timeout = null;
        window.focus();
        Stretchables.activeStretchable = draggable;
      }.bind(this), draggable.options.delay);
    } else {
      window.focus(); // allows keypress events if window isn't currently focused, fails for Safari
      this.activeStretchable = draggable;
    }
  },

  deactivate: function() {
    this.activeStretchable = null;
  },

  updateStretch: function(event) {
    if(!this.activeStretchable) return;
    var pointer = [Event.pointerX(event), Event.pointerY(event)];
    // Mozilla-based browsers fire successive mousemove events with
    // the same coordinates, prevent needless redrawing (moz bug?)
    if(this._lastPointer && (this._lastPointer.inspect() == pointer.inspect())) return;
    this._lastPointer = pointer;

    this.activeStretchable.updateStretch(event, pointer);
  },

  endStretch: function(event) {
    if(this._timeout) {
      clearTimeout(this._timeout);
      this._timeout = null;
    }
    if(!this.activeStretchable) return;
  this._lastPointer = null;
    this.activeStretchable.endStretch(event);
    this.activeStretchable = null;
  },

  keyPress: function(event) {
    if(this.activeStretchable)
      this.activeStretchable.keyPress(event);
  },

  addObserver: function(observer) {
    this.observers.push(observer);
    this._cacheObserverCallbacks();
  },

  removeObserver: function(element) {  // element instead of observer fixes mem leaks
    this.observers = this.observers.reject( function(o) { return o.element==element });
    this._cacheObserverCallbacks();
  },

  notify: function(eventName, draggable, event) {  // 'onStart', 'onEnd', 'onStretch'
    if(this[eventName+'Count'] > 0)
      this.observers.each( function(o) {
        if(o[eventName]) o[eventName](eventName, draggable, event);
      });
    if(draggable.options[eventName]) draggable.options[eventName](draggable, event);
  },

  _cacheObserverCallbacks: function() {
    ['onStart','onEnd','onStretch'].each( function(eventName) {
      Stretchables[eventName+'Count'] = Stretchables.observers.select(
        function(o) { return o[eventName]; }
      ).length;
    });
  }
}


var Stretchable = Class.create();
Stretchable._stretching    = {};
Stretchable.prototype = {
	initialize: function(element) {
		var defaults = {
			handle: false,
			reverteffect: function(element, width, height ) {
				var dur = Math.sqrt(Math.abs(width^2)+Math.abs(height^2))*0.02;
				new Effect.Scale(element, { width: width, height: height, duration: dur,
						queue: {scope:'_stretchable', position:'end'}
						});
			},
			endeffect: function(element) {
			   var toOpacity = typeof element._opacity == 'number' ? element._opacity : 1.0;
			   new Effect.Opacity(element, {duration:0.2, from:0.7, to:toOpacity,
					   queue: {scope:'_stretchable', position:'end'},
					   afterFinish: function(){
					   Stretchable._stretching[element] = false
					   }
					   });
			},
			zindex: 1000,
			revert: false,
			quiet: false,
			scroll: false,
			scrollSensitivity: 20,
			scrollSpeed: 15,
			snap: false,  // false, or xy or [x,y] or function(x,y){ return [x,y] }
			onChange:    Prototype.emptyFunction,
			delay: 0
		};

		if(!arguments[1] || typeof arguments[1].endeffect == 'undefined')
			Object.extend(defaults, {
				starteffect: function(element) {
					element._opacity = Element.getOpacity(element);
					Stretchable._stretching[element] = true;
					new Effect.Opacity(element, {duration:0.2, from:element._opacity, to:0.7});
				}
			});

		var options = Object.extend(defaults, arguments[1] || {});

		this.element = $(element);

		if(options.handle && (typeof options.handle == 'string'))
			this.handle = this.element.down('.'+options.handle, 0);

		if(!this.handle) this.handle = $(options.handle);
		if(!this.handle) this.handle = this.element;

		if(options.scroll && !options.scroll.scrollTo && !options.scroll.outerHTML) {
			options.scroll = $(options.scroll);
			this._isScrollChild = Element.childOf(this.element, options.scroll);
		}

		Element.makePositioned(this.element); // fix IE

		this.delta    = this.currentDelta();
		this.options  = options;
		this.stretching = false;

		this.eventMouseDown = this.initStretch.bindAsEventListener(this);
		Event.observe(this.handle, "mousedown", this.eventMouseDown);

		Stretchables.register(this);
	},

	destroy: function() {
			 Event.stopObserving(this.handle, "mousedown", this.eventMouseDown);
			Stretchables.unregister(this);
		 },

	currentDelta: function() {
			  return([
					  parseInt(Element.getStyle(this.element,'width') || '0'),
					  parseInt(Element.getStyle(this.element,'height') || '0')]);
		  },

	initStretch: function( event ) {
		if(typeof Stretchable._stretching[this.element] != 'undefined' && Stretchable._stretching[this.element]) return;
var shiftKey = event.modifiers? event.modifiers&Event.SHIFT_MASK : (event.shiftKey || false);
		if(shiftKey && Event.isLeftClick(event)) {
			// abort on form elements, fixes a Firefox issue
			var src = Event.element(event);
			if((tag_name = src.tagName.toUpperCase()) && (
						tag_name=='INPUT' ||
						tag_name=='SELECT' ||
						tag_name=='OPTION' ||
						tag_name=='BUTTON' ||
						tag_name=='TEXTAREA')) return;

			var pointer = [Event.pointerX(event), Event.pointerY(event)];
			this.start_pointer = pointer;
			this.start_size = this.currentDelta();

			Stretchables.activate(this);
			Event.stop(event);
		} // end if
	 },
	startStretch: function(event) {
		this.stretching = true;

		if(this.options.zindex) {
			this.originalZ = parseInt(Element.getStyle(this.element,'z-index') || 0);
			this.element.style.zIndex = this.options.zindex;
		}

		if(this.options.scroll) {
			if (this.options.scroll == window) {
				var where = this._getWindowScroll(this.options.scroll);
				this.originalScrollLeft = where.left;
				this.originalScrollTop = where.top;
			} else {
				this.originalScrollLeft = this.options.scroll.scrollLeft;
				this.originalScrollTop = this.options.scroll.scrollTop;
			}
		}

		Stretchables.notify('onStart', this, event);

		if(this.options.starteffect) this.options.starteffect(this.element);
	},

	updateStretch: function(event, pointer) {
		if(!this.stretching) this.startStretch(event);

		if(!this.options.quiet){
			Position.prepare();
			//Droppables.show(pointer, this.element);
		}

		Stretchables.notify('onStretch', this, event);

		this.draw(pointer);
		if(this.options.change) this.options.change(this);

		if(this.options.scroll) {
			this.stopScrolling();

			var p;
			if (this.options.scroll == window) {
				with(this._getWindowScroll(this.options.scroll)) { p = [ left, top, left+width, top+height ]; }
			} else {
				p = Position.page(this.options.scroll);
				p[0] += this.options.scroll.scrollLeft + Position.deltaX;
				p[1] += this.options.scroll.scrollTop + Position.deltaY;
				p.push(p[0]+this.options.scroll.offsetWidth);
				p.push(p[1]+this.options.scroll.offsetHeight);
			}
			var speed = [0,0];
			if(pointer[0] < (p[0]+this.options.scrollSensitivity)) speed[0] = pointer[0]-(p[0]+this.options.scrollSensitivity);
			if(pointer[1] < (p[1]+this.options.scrollSensitivity)) speed[1] = pointer[1]-(p[1]+this.options.scrollSensitivity);
			if(pointer[0] > (p[2]-this.options.scrollSensitivity)) speed[0] = pointer[0]-(p[2]-this.options.scrollSensitivity);
			if(pointer[1] > (p[3]-this.options.scrollSensitivity)) speed[1] = pointer[1]-(p[3]-this.options.scrollSensitivity);
			this.startScrolling(speed);
		}

		// fix AppleWebKit rendering
		if(Prototype.Browser.WebKit) window.scrollBy(0,0);

		Event.stop(event);
	},

	finishStretch: function(event, success) {
		this.stretching = false;

		if(this.options.quiet){
			Position.prepare();
			var pointer = [Event.pointerX(event), Event.pointerY(event)];
			//Droppables.show(pointer, this.element);
		}

		var dropped = false;
		if(success) {
			//dropped = Stretchables.fire(event, this.element);
			if (!dropped) dropped = false;
		}
		if(dropped && this.options.onDropped) this.options.onDropped(this.element);
		Stretchables.notify('onEnd', this, event);

		var revert = this.options.revert;
		if(revert && typeof revert == 'function') revert = revert(this.element);
		var d = this.currentDelta();
		if(revert && this.options.reverteffect) {
			if (dropped == 0 || revert != 'failure')
				this.options.reverteffect(this.element, d[1]-this.delta[1], d[0]-this.delta[0]);
		} else {
			this.delta = d;
		}

		if(this.options.zindex)
			this.element.style.zIndex = this.originalZ;

		if(this.options.endeffect)
			this.options.endeffect(this.element);

		Stretchables.deactivate(this);
		this.options.onChange(this.element);
	},
	keyPress: function(event) {
		if(event.keyCode!=Event.KEY_ESC) return;
		this.finishStretch(event, false);
		Event.stop(event);
	},

	endStretch: function(event) {
		if(!this.stretching) return;
		this.stopScrolling();
		this.finishStretch(event, true);
		Event.stop(event);
	},

	draw: function(point) {
		var pos = [0,1].map(function(i){
				return (this.start_pointer[i])
				}.bind(this));

		var d = this.start_size;
		pos[0] = d[0] + ( point[0]-pos[0]);
		pos[1] = d[1] + ( point[1]-pos[1]);

		if(this.options.scroll && (this.options.scroll != window && this._isScrollChild)) {
			pos[0] -= this.options.scroll.scrollLeft-this.originalScrollLeft;
			pos[1] -= this.options.scroll.scrollTop-this.originalScrollTop;
		}

		var p = [0,1].map(function(i){
				return (pos[i])
				}.bind(this));

		if(this.options.snap) {
			if(typeof this.options.snap == 'function') {
				p = this.options.snap(p[0],p[1],this);
			} else {
				if(this.options.snap instanceof Array) {
					p = p.map( function(v, i) {
							return Math.round(v/this.options.snap[i])*this.options.snap[i] }.bind(this))
				} else {
					p = p.map( function(v) {
							return Math.round(v/this.options.snap)*this.options.snap }.bind(this))
				}
			}}

		var style = this.element.style;
		if((!this.options.constraint) || (this.options.constraint=='horizontal'))
			style.width = p[0] + "px";
		if((!this.options.constraint) || (this.options.constraint=='vertical'))
			style.height  = p[1] + "px";

		if(style.visibility=="hidden") style.visibility = ""; // fix gecko rendering
	},

	stopScrolling: function() {
	   if(this.scrollInterval) {
		   clearInterval(this.scrollInterval);
		   this.scrollInterval = null;
		   Stretchables._lastScrollPointer = null;
	   }
	},

	startScrolling: function(speed) {
		if(!(speed[0] || speed[1])) return;
		this.scrollSpeed = [speed[0]*this.options.scrollSpeed,speed[1]*this.options.scrollSpeed];
		this.lastScrolled = new Date();
		this.scrollInterval = setInterval(this.scroll.bind(this), 10);
	},

	scroll: function() {
		var current = new Date();
		var delta = current - this.lastScrolled;
		this.lastScrolled = current;
		if(this.options.scroll == window) {
			with (this._getWindowScroll(this.options.scroll)) {
				if (this.scrollSpeed[0] || this.scrollSpeed[1]) {
					var d = delta / 1000;
					this.options.scroll.scrollTo( left + d*this.scrollSpeed[0], top + d*this.scrollSpeed[1] );
				}
			}
		} else {
			this.options.scroll.scrollLeft += this.scrollSpeed[0] * delta / 1000;
			this.options.scroll.scrollTop  += this.scrollSpeed[1] * delta / 1000;
		}

		Position.prepare();
		Stretchables.show(Stretchables._lastPointer, this.element);
		Stretchables.notify('onStretch', this);
		if (this._isScrollChild) {
			Stretchables._lastScrollPointer = Stretchables._lastScrollPointer || $A(Stretchables._lastPointer);
			Stretchables._lastScrollPointer[0] += this.scrollSpeed[0] * delta / 1000;
			Stretchables._lastScrollPointer[1] += this.scrollSpeed[1] * delta / 1000;
			if (Stretchables._lastScrollPointer[0] < 0)
				Stretchables._lastScrollPointer[0] = 0;
			if (Stretchables._lastScrollPointer[1] < 0)
				Stretchables._lastScrollPointer[1] = 0;
			this.draw(Stretchables._lastScrollPointer);
		}

		if(this.options.change) this.options.change(this);
	},

	_getWindowScroll: function(w) {
		  var T, L, W, H;
		  with (w.document) {
			  if (w.document.documentElement && documentElement.scrollTop) {
				  T = documentElement.scrollTop;
				  L = documentElement.scrollLeft;
			  } else if (w.document.body) {
				  T = body.scrollTop;
				  L = body.scrollLeft;
			  }
			  if (w.innerWidth) {
				  W = w.innerWidth;
				  H = w.innerHeight;
			  } else if (w.document.documentElement && documentElement.clientWidth) {
				  W = documentElement.clientWidth;
				  H = documentElement.clientHeight;
			  } else {
				  W = body.offsetWidth;
				  H = body.offsetHeight
			  }
		  }
		  return { top: T, left: L, width: W, height: H };
	}
} // end prototype

