# MIT License
# 
# Copyright (c) 2023 Can Joshua Lehmann
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Utilities for wrapping widgets

import gtk, widgetdef

proc redraw*[T](event: EventObj[T]) =
  if event.app.isNil:
    raise newException(ValueError, "App is nil")
  event.app.redraw()

proc eventCallback*(widget: GtkWidget, data: ptr EventObj[proc ()]) =
  data[].callback()
  data[].redraw()

proc connect*[T](renderable: Renderable,
                 event: Event[T],
                 name: cstring,
                 eventCallback: pointer) =
  if not event.isNil:
    event.widget = renderable
    event.handler = g_signal_connect(renderable.internalWidget, name, eventCallback, event[].addr)

proc disconnect*[T](widget: GtkWidget, event: Event[T]) =
  if not event.isNil:
    assert event.handler > 0
    g_signal_handler_disconnect(widget, event.handler)
    event.handler = 0
    event.widget = nil

proc updateStyle*[State, Widget](state: State, widget: Widget) =
  mixin classes
  if widget.hasStyle:
    let ctx = gtk_widget_get_style_context(state.internalWidget)
    for styleClass in state.style - widget.valStyle:
      gtk_style_context_remove_class(ctx, cstring($styleClass))
    for styleClass in widget.valStyle - state.style:
      gtk_style_context_add_class(ctx, cstring($styleClass))
    state.style = widget.valStyle

proc updateChild*(state: Renderable,
                  child: var WidgetState,
                  updater: Widget,
                  setChild: proc(widget, child: GtkWidget) {.cdecl.}) =
  if updater.isNil:
    if not child.isNil:
      child = nil
      setChild(state.internalWidget, nil)
  else:
    updater.assignApp(state.app)
    if child.isNil:
      child = updater.build()
      setChild(state.internalWidget, unwrapInternalWidget(child))
    else:
      let newChild = updater.update(child)
      if not newChild.isNil:
        child = newChild
        setChild(state.internalWidget, unwrapInternalWidget(child))

proc updateChildren*(state: Renderable,
                     children: var seq[WidgetState],
                     updates: seq[Widget],
                     addChild: proc(widget, child: GtkWidget) {.cdecl.},
                     removeChild: proc(widget, child: GtkWidget) {.cdecl.}) =
  updates.assignApp(state.app)
  
  var
    it = 0
    forceReadd = false
  while it < updates.len and it < children.len:
    let newChild = updates[it].update(children[it])
    if not newChild.isNil:
      removeChild(state.internalWidget, children[it].unwrapInternalWidget())
      addChild(state.internalWidget, newChild.unwrapInternalWidget())
      children[it] = newChild
      forceReadd = true
    elif forceReadd:
      removeChild(state.internalWidget, children[it].unwrapInternalWidget())
      addChild(state.internalWidget, children[it].unwrapInternalWidget())
    it += 1
  
  while it < updates.len:
    let
      child = updates[it].build()
      childWidget = child.unwrapInternalWidget()
    addChild(state.internalWidget, childWidget)
    children.add(child)
    it += 1
  
  while it < children.len:
    removeChild(state.internalWidget, children[it].unwrapInternalWidget())
    children.del(it)

proc updateChildren*(state: Renderable,
                     children: var seq[WidgetState],
                     updates: seq[Widget],
                     addChild: proc(widget, child: GtkWidget) {.cdecl.},
                     insertChild: proc(widget, child: GtkWidget, index: cint) {.cdecl.},
                     removeChild: proc(widget, child: GtkWidget) {.cdecl.}) =
  updates.assignApp(state.app)
  
  var it = 0
  while it < updates.len and it < children.len:
    let newChild = updates[it].update(children[it])
    if not newChild.isNil:
      removeChild(state.internalWidget, unwrapInternalWidget(children[it]))
      insertChild(
        state.internalWidget,
        unwrapInternalWidget(newChild),
        cint(it)
      )
      children[it] = newChild
    it += 1
  
  while it < updates.len:
    let child = updates[it].build()
    addChild(state.internalWidget, unwrapInternalWidget(child))
    children.add(child)
    it += 1
  
  while it < children.len:
    let child = unwrapInternalWidget(children.pop())
    removeChild(state.internalWidget, child)

type
  Align* = enum
    AlignFill, AlignStart, AlignEnd, AlignCenter
  
  AlignedChild*[T] = object
    widget*: T
    hAlign*: Align
    vAlign*: Align

proc assignApp(child: AlignedChild[Widget], app: Viewable) =
  child.widget.assignApp(app)

proc toGtk*(align: Align): GtkAlign = GtkAlign(ord(align))

proc updateAlignedChildren*(state: Renderable,
                            children: var seq[AlignedChild[WidgetState]],
                            updates: seq[AlignedChild[Widget]],
                            addChild: proc(widget, child: GtkWidget) {.cdecl.},
                            removeChild: proc(widget, child: GtkWidget) {.cdecl.}) =
  updates.assignApp(state.app)
  var
    it = 0
    forceReadd = false
  while it < updates.len and it < children.len:
    let newChild = update(updates[it].widget, children[it].widget)
    
    if not newChild.isNil:
      removeChild(state.internalWidget, children[it].widget.unwrapInternalWidget())
      addChild(state.internalWidget, newChild.unwrapInternalWidget())
      children[it].widget = newChild
      forceReadd = true
    elif forceReadd:
      removeChild(state.internalWidget, children[it].widget.unwrapInternalWidget())
      addChild(state.internalWidget, children[it].widget.unwrapInternalWidget())
    
    let childWidget = children[it].widget.unwrapInternalWidget()
    
    if not newChild.isNil or updates[it].hAlign != children[it].hAlign:
      gtk_widget_set_halign(childWidget, toGtk(updates[it].hAlign))
      children[it].hAlign = updates[it].hAlign
    
    if not newChild.isNil or updates[it].vAlign != children[it].vAlign:
      gtk_widget_set_valign(childWidget, toGtk(updates[it].vAlign))
      children[it].vAlign = updates[it].vAlign
    
    it += 1
  
  while it < updates.len:
    let
      childState = updates[it].widget.build()
      childWidget = childState.unwrapInternalWidget()
    gtk_widget_set_halign(childWidget, toGtk(updates[it].hAlign))
    gtk_widget_set_valign(childWidget, toGtk(updates[it].vAlign))
    addChild(state.internalWidget, childWidget)
    children.add(AlignedChild[WidgetState](
      widget: childState,
      hAlign: updates[it].hAlign,
      vAlign: updates[it].vAlign
    ))
    it += 1
  
  while it < children.len:
    let child = children.pop()
    removeChild(state.internalWidget, child.widget.unwrapInternalWidget())
