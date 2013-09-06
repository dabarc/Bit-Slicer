/*
 * Created by Mayur Pawashe on 9/5/13.
 *
 * Copyright (c) 2013 zgcoder
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * Neither the name of the project's author nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "ZGPyDebugger.h"
#import "ZGAppController.h"
#import "ZGDebuggerController.h"
#import "ZGLoggerWindowController.h"
#import <Python/structmember.h>

typedef struct
{
	PyObject_HEAD
	uint32_t processTask;
	char is64Bit;
} DebuggerClass;

static PyMemberDef Debugger_members[] =
{
	{NULL, 0, 0, 0, NULL}
};

#define declareDebugPrototypeMethod(name) static PyObject *Debugger_##name(DebuggerClass *self, PyObject *args);

declareDebugPrototypeMethod(assemble)

#define declareDebugMethod2(name, argsType) {#name"", (PyCFunction)Debugger_##name, argsType, NULL},
#define declareDebugMethod(name) declareDebugMethod2(name, METH_VARARGS)

static PyMethodDef Debugger_methods[] =
{
	declareDebugMethod(assemble)
	{NULL, NULL, 0, NULL}
};

static PyTypeObject DebuggerType =
{
	PyObject_HEAD_INIT(NULL)
	0, // ob_size
	"bitslicer.Debugger", // tp_name
	sizeof(DebuggerClass), // tp_basicsize
	0, // tp_itemsize
	0, // tp_dealloc
	0, // tp_print
	0, // tp_getattr
	0, // tp_setattr
	0, // tp_compare
	0, // tp_repr
	0, // tp_as_number
	0, // tp_as_sequence
	0, // tp_as_mapping
	0, // tp_hash
	0, // tp_call
	0, // tp_str
	0, // tp_getattro
	0, // tp_setattro
	0, // tp_as_buffer
	Py_TPFLAGS_DEFAULT, // tp_flags
	"Debugger objects", // tp_doc
	0, // tp_traverse
	0, // tp_clear
	0, // tp_richcompare
	0, // tp_weaklistoffset
	0, // tp_iter
	0, // tp_iternext
	Debugger_methods, // tp_methods
	Debugger_members, // tp_members
	0, // tp_getset
	0, // tp_base
	0, // tp_dict
	0, // tp_descr_get
	0, // tp_descr_set
	0, // tp_dictoffset
	0, // tp_init
	0, // tp_alloc
	0, // tp_new
	0, 0, 0, 0, 0, 0, 0, 0, 0 // the rest
};

@implementation ZGPyDebugger

+ (void)loadPythonClassInMainModule:(PyObject *)module
{
	DebuggerType.tp_new = PyType_GenericNew;
	if (PyType_Ready(&DebuggerType) >= 0)
	{
		Py_INCREF(&DebuggerType);
		
		PyModule_AddObject(module, "Debugger", (PyObject *)&DebuggerType);
	}
	else
	{
		NSLog(@"Error: DebuggerType was not ready!");
	}
}

- (id)initWithProcessTask:(ZGMemoryMap)processTask is64Bit:(BOOL)is64Bit
{
	self = [super init];
	if (self != nil)
	{
		PyTypeObject *type = &DebuggerType;
		self.object = (PyObject *)((DebuggerClass *)type->tp_alloc(type, 0));
		if (self.object == NULL)
		{
			return nil;
		}
		DebuggerClass *debuggerObject = (DebuggerClass *)self.object;
		debuggerObject->processTask = processTask;
		debuggerObject->is64Bit = is64Bit;
	}
	return self;
}

- (void)setObject:(PyObject *)object
{
	if (Py_IsInitialized())
	{
		Py_XDECREF(_object);
	}
	_object = object;
}

- (void)dealloc
{
	self.object = NULL;
}

static PyObject *Debugger_assemble(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress instructionPointer = 0;
	char *codeString = NULL;
	
	if (PyArg_ParseTuple(args, "sK", &codeString, &instructionPointer))
	{
		NSError *error = nil;
		NSData *assembledData = [[[ZGAppController sharedController] debuggerController] assembleInstructionText:@(codeString) atInstructionPointer:instructionPointer usingArchitectureBits:self->is64Bit ? sizeof(int64_t)*8 : sizeof(int32_t)*8 error:&error];
		
		if (error == nil)
		{
			retValue = Py_BuildValue("s#", assembledData.bytes, assembledData.length);
		}
		else
		{
			NSLog(@"Error: couldn't assemble data");
			NSLog(@"%@", error);
			dispatch_async(dispatch_get_main_queue(), ^{
				[[[ZGAppController sharedController] loggerController] writeLine:[[error userInfo] objectForKey:@"reason"]];
				if ([[error userInfo] objectForKey:@"description"] != nil)
				{
					[[[ZGAppController sharedController] loggerController] writeLine:[[error userInfo] objectForKey:@"description"]];
				}
			});
		}
	}
	
	return retValue;
}

@end
