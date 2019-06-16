//
//  TTContext.m
//  TTPatch
//
//  Created by ty on 2019/5/17.
//  Copyright © 2019 TianyuBing. All rights reserved.
//

#import "TTContext.h"
#import "TTPatchUtils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "TTPatch.h"
#import <libkern/OSAtomic.h>
NSString *const TTPatchChangeMethodPrefix = @"tt";

#define guard(condfion) if(condfion){}



@interface TTContext ()
@end

@implementation TTContext
static NSMutableDictionary *__replaceMethodMap;

static void aspect_performLocked(dispatch_block_t block) {
    static OSSpinLock aspect_lock = OS_SPINLOCK_INIT;
    OSSpinLockLock(&aspect_lock);
    block();
    OSSpinLockUnlock(&aspect_lock);
}

void registerMethod(NSString *method,NSString *class,BOOL isClass){
    if (!__replaceMethodMap) {
        __replaceMethodMap = [NSMutableDictionary dictionary];
    }
    TTMethodList_Node *node = [TTMethodList_Node createNodeCls:class methodName:method isClass:isClass];
    [__replaceMethodMap setObject:node forKey:node.key];
}

BOOL checkRegistedMethod(NSString *method, NSString *class, BOOL isClass){
    TTMethodList_Node *node = [TTMethodList_Node createNodeCls:class methodName:method isClass:isClass];
    if ([__replaceMethodMap objectForKey:node.key]) {
        return YES;
    }
    return NO;
}
    
void OC_MSG_SEND_HANDLE_VOID(id self, SEL _cmd,...){
    @synchronized (self) {
        JSValue * func = [TTPatch shareInstance].context[@"js_msgSend"];
         [func callWithArguments:@[[JSValue valueWithObject:self inContext:[TTPatch shareInstance].context],NSStringFromClass([self class]),TTPatchUtils.TTPatchMethodFormatterToJSFunc(NSStringFromSelector(_cmd)),@"params"]];
    }
}

#define WRAP_AND_RETURN(argType,vauleType)\
case argType:{  \
vauleType tempArg = va_arg(argList, vauleType); \
[tempArguments addObject:@(tempArg)];}break

id OC_MSG_SEND_HANDLE_ID(id self, SEL _cmd,...){
    @synchronized (self) {
        JSValue * func = [TTPatch shareInstance].context[@"js_msgSend"];
        Method methodInfo = TTPatchUtils.TTPatchGetInstanceOrClassMethodInfo([self class],_cmd);
        NSLog(@"%s",method_getTypeEncoding(methodInfo));
        char *retType = method_copyReturnType(methodInfo);
        int indexOffset = 2;
        int systemMethodArgCount = method_getNumberOfArguments(methodInfo);
        if (systemMethodArgCount>indexOffset) {
            systemMethodArgCount-=indexOffset;
        }else{
            systemMethodArgCount=0;
        }
     
        NSMutableArray *tempArguments = [NSMutableArray arrayWithCapacity:systemMethodArgCount];
        va_list argList;
        va_start(argList, _cmd);
        for (int i = 0; i < systemMethodArgCount; i++) {
            const char *argumentType = method_copyArgumentType(methodInfo, i+indexOffset);
            switch(argumentType[0] == 'r' ? argumentType[1] : argumentType[0]) {
                case _C_ID:{
                    id tempArg = va_arg(argList, id);
                    [tempArguments addObject:tempArg];}
                    break;
                    WRAP_AND_RETURN(_C_INT, int);
                    WRAP_AND_RETURN(_C_SHT, short);
                    WRAP_AND_RETURN(_C_USHT, unsigned short);
                    WRAP_AND_RETURN(_C_UINT, unsigned int);
                    WRAP_AND_RETURN(_C_LNG, long);
                    WRAP_AND_RETURN(_C_ULNG, unsigned long);
                    WRAP_AND_RETURN(_C_LNG_LNG, long long);
                    WRAP_AND_RETURN(_C_ULNG_LNG, unsigned long long);
                    WRAP_AND_RETURN(_C_FLT, float);
                    WRAP_AND_RETURN(_C_DBL, double);
                    WRAP_AND_RETURN(_C_BOOL, BOOL);
                    

            }
        }
        va_end(argList);

        
    
//        NSLog(@"-----%@",_cmd);
 
        
        NSMutableArray * params = [@[[JSValue valueWithObject:self inContext:[TTPatch shareInstance].context],NSStringFromClass([self class]),TTPatchUtils.TTPatchMethodFormatterToJSFunc(NSStringFromSelector(_cmd)),@"params"] mutableCopy];
        [params addObjectsFromArray:tempArguments];
        JSValue *result = [func callWithArguments:params];
        return result;
    }
    
}

static void registerJsMethod(NSString *className,NSString *superClassName,NSString *method,BOOL isInstanceMethod){
    replaceOcOriginalMethod(className, superClassName, method, isInstanceMethod, nil);
}

static void replaceOcOriginalMethod(NSString *className,NSString *superClassName,NSString *method,BOOL isInstanceMethod, NSArray *arguments){
    if(checkRegistedMethod(method, className, !isInstanceMethod)){
        return;
    }
    
    NSLog(@"%@替换 %@ %@", className, isInstanceMethod?@"-":@"+", method);
    Class aClass = NSClassFromString(className);
    SEL original_SEL = NSSelectorFromString(method);
    Method originalMethodInfo = class_getInstanceMethod(aClass, original_SEL);

    BOOL needRegistClass=NO;
    if (aClass) {
    }else{
        aClass = objc_allocateClassPair(NSClassFromString(superClassName), [className UTF8String], 0);
        needRegistClass = YES;
    }
    
    //如果是实例方法
    guard(isInstanceMethod) else{
        originalMethodInfo = class_getClassMethod(aClass, original_SEL);
        aClass = object_getClass(aClass);
    }
    const char *methodTypes = method_getTypeEncoding(originalMethodInfo)?: "v@:";
    NSLog(@"--------方法描述:%s\n 返回值描述:%s",method_getTypeEncoding(originalMethodInfo),method_copyReturnType(originalMethodInfo));

    IMP original_IMP = class_getMethodImplementation(aClass, original_SEL);
    SEL new_SEL = NSSelectorFromString([NSString stringWithFormat:@"%@%@", TTPatchChangeMethodPrefix, method]);
    //如果不存在直接添加方法
    BOOL status = class_addMethod(aClass, original_SEL, (IMP)OC_MSG_SEND_HANDLE_ID, methodTypes);
    if (!status) {
        class_replaceMethod(aClass, original_SEL, (IMP)OC_MSG_SEND_HANDLE_ID, methodTypes);
        if (class_addMethod(aClass, new_SEL, original_IMP, methodTypes)) {
            
        }else{
            class_replaceMethod(aClass, new_SEL, original_IMP, methodTypes);
        }
    }
    
    registerMethod(method, className, !isInstanceMethod);
    
    if (needRegistClass) {
        objc_registerClassPair(aClass);
    }
    
    unsigned int count;
    Method *methods = class_copyMethodList(aClass, &count);
    for (int i = 0; i < count; i++) {
        Method method = methods[i];
        SEL selector = method_getName(method);
        NSString *name = NSStringFromSelector(selector);
        NSLog(@"%@ method_getName:%@",NSStringFromClass(aClass),name);
    }
    
    unsigned int numIvars;
    Ivar *vars = class_copyIvarList(aClass, &numIvars);
    NSString *key=nil;
    for(int i = 0; i < numIvars; i++) {
        
        Ivar thisIvar = vars[i];
        key = [NSString stringWithUTF8String:ivar_getName(thisIvar)];
        NSLog(@"%@ variable_name :%@", NSStringFromClass(aClass),key);
    }
    free(vars);
}

static BOOL aspect_isMsgForwardIMP(IMP impl) {
    return impl == _objc_msgForward
#if !defined(__arm64__)
    || impl == (IMP)_objc_msgForward_stret
#endif
    ;
}

static IMP aspect_getMsgForwardIMP(Class aclass, SEL selector,BOOL isInstanceMethod) {
    IMP msgForwardIMP = _objc_msgForward;
#if !defined(__arm64__)
    // As an ugly internal runtime implementation detail in the 32bit runtime, we need to determine of the method we hook returns a struct or anything larger than id.
    // https://developer.apple.com/library/mac/documentation/DeveloperTools/Conceptual/LowLevelABI/000-Introduction/introduction.html
    // https://github.com/ReactiveCocoa/ReactiveCocoa/issues/783
    // http://infocenter.arm.com/help/topic/com.arm.doc.ihi0042e/IHI0042E_aapcs.pdf (Section 5.4)
    Method method;
    if (isInstanceMethod) {
        method = class_getInstanceMethod(aclass, selector);
    }else{
        method = class_getClassMethod(aclass, selector);
    }
    
    const char *encoding = method_getTypeEncoding(method)?:"v@:";
    BOOL methodReturnsStructValue = encoding[0] == _C_STRUCT_B;
    if (methodReturnsStructValue) {
        @try {
            NSUInteger valueSize = 0;
            NSGetSizeAndAlignment(encoding, &valueSize, NULL);
            
            if (valueSize == 1 || valueSize == 2 || valueSize == 4 || valueSize == 8) {
                methodReturnsStructValue = NO;
            }
        } @catch (__unused NSException *e) {}
    }
    if (methodReturnsStructValue) {
        msgForwardIMP = (IMP)_objc_msgForward_stret;
    }
#endif
    return msgForwardIMP;
}

static void hookClassMethod(NSString *className,NSString *superClassName,NSString *method,BOOL isInstanceMethod){
    if(checkRegistedMethod(method, className, !isInstanceMethod)){
        return;
    }
    static NSSet *disallowedSelectorList;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        disallowedSelectorList = [NSSet setWithObjects:@"retain", @"release", @"autorelease", @"forwardInvocation:", nil];
    });
    
    
    if ([disallowedSelectorList containsObject:method]) {
        NSString *errorDescription = [NSString stringWithFormat:@"Selector %@ is blacklisted.", method];
//        AspectError(AspectErrorSelectorBlacklisted, errorDescription);
        NSCAssert(NO, errorDescription);
    }

    
    NSLog(@"%@替换 %@ %@", className, isInstanceMethod?@"-":@"+", method);
    Class aClass = NSClassFromString(className);
    SEL original_SEL = NSSelectorFromString(method);
    Method originalMethodInfo = class_getInstanceMethod(aClass, original_SEL);
    
    BOOL needRegistClass=NO;
    if (aClass) {
    }else{
        aClass = objc_allocateClassPair(NSClassFromString(superClassName), [className UTF8String], 0);
        needRegistClass = YES;
    }
    
    //如果是实例方法
    guard(isInstanceMethod) else{
        originalMethodInfo = class_getClassMethod(aClass, original_SEL);
        aClass = object_getClass(aClass);
    }
//    const char *methodTypes = method_getTypeEncoding(originalMethodInfo)?: "v@:";
//    NSLog(@"--------方法描述:%s\n 返回值描述:%s",method_getTypeEncoding(originalMethodInfo),method_copyReturnType(originalMethodInfo));
//
//    IMP original_IMP = class_getMethodImplementation(aClass, original_SEL);
//    SEL new_SEL = NSSelectorFromString([NSString stringWithFormat:@"%@%@", TTPatchChangeMethodPrefix, method]);
//    //如果不存在直接添加方法
//    BOOL status = class_addMethod(aClass, original_SEL, aspect_getMsgForwardIMP(aClass,original_SEL,isInstanceMethod), methodTypes);
//    if (!status) {
//        class_replaceMethod(aClass, original_SEL, aspect_getMsgForwardIMP(aClass,original_SEL,isInstanceMethod), methodTypes);
//        if (class_addMethod(aClass, new_SEL, original_IMP, methodTypes)) {
//
//        }else{
//            class_replaceMethod(aClass, new_SEL, original_IMP, methodTypes);
//        }
//    }
    
    /**
     *  这里为什么要替换 `ForwardInvocation` 而不是替换对应方法要解释一下
     *  因为添加的 `IMP` 是固定的函数,而函数的返回值类型,以及返回值有无,在写的时候就已经固定了.所以我们会面临两个问题
     *  1.要根据当前被替换方法返回值类型,提前注册好对应的`IMP`函数,使得函数能拿到正确的数据类型.
     *  2.要如何知道当前方法是否有返回值,以及返回值的类型是什么?
     *
     *  因为这两个原因很麻烦,当然是用 穷举+方法返回值加标识 可以解决这个问题,但是我感觉这么做是一个坑.最后找到根据 `aspect` 和 `JSPatch`的作者blog,为什么他们都要hook `ForwardInvocation` 这个方法.其实原因很简单,在这个时候我们能够拿到当前系统调用中方法的 `invocation` 对象,也就意味着能够拿到当前方法的全部信息,而且我们此时也能去根据`js`替换后方法的返回值去`set`当前`invocation`对象的返回值,使当前无论返回值使什么类型,我们都可以根据当前的方法签名来对应为其转换为相应类型.
     */
    aspect_swizzleForwardInvocation(aClass);
    /**
     *  将要我换的方法IMP替换成`_objc_msgForward`,这么做的原因其实是为了优化方法调用时间.
     *  假如我们不做方法替换,系统在执行`objc_msgSend`函数,这样会根据当前的对象的继承链去查找方法然后执行,这里就涉及到一个查找的过程
     *  如果查找不到方法,会走消息转发也就是`_objc_msgForward`函数做的事情,所以那我们为什么不直接将方法的`IMP`替换为`_objc_msgForward`直接走消息转发呢
     */
    aspect_prepareClassAndHookSelector(aClass, original_SEL, isInstanceMethod);
    
    //将已经替换的class做记录
    registerMethod(method, className, !isInstanceMethod);
    
    if (needRegistClass) {
        objc_registerClassPair(aClass);
    }
    
  
}


#define WRAP_INVOCATION_AND_RETURN(argType,vauleType)\
case argType:{  \
vauleType tempArg; \
[invocation getArgument:&tempArg atIndex:(i)];    \
[tempArguments addObject:@(tempArg)];  \
}break

#define WRAP_INVOCATION_ID_AND_RETURN(argType,vauleType)\
case argType:{  \
__unsafe_unretained vauleType tempArg; \
[invocation getArgument:&tempArg atIndex:(i)];    \
[tempArguments addObject:tempArg];  \
}break

#define WRAP_INVOCATION_RETURN_VALUE(argType,valueType,toValueFunc) \
case argType:{  \
valueType result = [[jsValue toNumber] toValueFunc];    \
[invocation setReturnValue:&result];    \
}break;

#define WRAP_INVOCATION_ID_RETURN_VALUE(argType,valueType,toValueFunc) \
case argType:{  \
__unsafe_unretained valueType result = [jsValue toValueFunc];    \
[invocation setReturnValue:&result];    \
}break;


static void OC_MSG_SEND_HANDLE(__unsafe_unretained NSObject *self, SEL invocation_selector, NSInvocation *invocation) {
    @synchronized (self) {
        
        JSValue * func = [TTPatch shareInstance].context[@"js_msgSend"];
        Method methodInfo = TTPatchUtils.TTPatchGetInstanceOrClassMethodInfo([self class],invocation.selector);
        
        char *returnValueType=(char *)malloc(sizeof(char *));
        strcpy(returnValueType, [invocation.methodSignature methodReturnType]);
        unsigned int indexOffset = 0;
        unsigned int systemMethodArgCount = (unsigned int)invocation.methodSignature.numberOfArguments;

        if (systemMethodArgCount>2) {
            indexOffset = 2;
        }
        NSLog(@"\n--------------------------- JS 调用 OC ----------------%s \n----->%@      \n----->%@  \n----->%d",method_getTypeEncoding(methodInfo),NSStringFromSelector(invocation.selector),self,systemMethodArgCount);
        NSMutableArray *tempArguments = [NSMutableArray arrayWithCapacity:systemMethodArgCount];
        
        for (unsigned i = indexOffset; i < systemMethodArgCount; i++) {
            const char *argumentType = method_copyArgumentType(methodInfo, i);
            switch(argumentType[0] == 'r' ? argumentType[1] : argumentType[0]) {
//                    WRAP_INVOCATION_ID_AND_RETURN(_C_ID, id);
                case _C_ID:{  \
                    __unsafe_unretained id tempArg; \
                    [invocation getArgument:&tempArg atIndex:(i)];    \
                    [tempArguments addObject:tempArg];  \
                }break;
                    WRAP_INVOCATION_AND_RETURN(_C_INT, int);
                    WRAP_INVOCATION_AND_RETURN(_C_SHT, short);
                    WRAP_INVOCATION_AND_RETURN(_C_USHT, unsigned short);
                    WRAP_INVOCATION_AND_RETURN(_C_UINT, unsigned int);
                    WRAP_INVOCATION_AND_RETURN(_C_LNG, long);
                    WRAP_INVOCATION_AND_RETURN(_C_ULNG, unsigned long);
                    WRAP_INVOCATION_AND_RETURN(_C_LNG_LNG, long long);
                    WRAP_INVOCATION_AND_RETURN(_C_ULNG_LNG, unsigned long long);
                    WRAP_INVOCATION_AND_RETURN(_C_FLT, float);
                    WRAP_INVOCATION_AND_RETURN(_C_DBL, double);
                    WRAP_INVOCATION_AND_RETURN(_C_BOOL, BOOL);
                    
            }
        }
        
   
        
        
        NSMutableArray * params = [@[[JSValue valueWithObject:self inContext:[TTPatch shareInstance].context],NSStringFromClass([self class]),TTPatchUtils.TTPatchMethodFormatterToJSFunc(NSStringFromSelector(invocation.selector))] mutableCopy];
        [params addObjectsFromArray:tempArguments];
        __unsafe_unretained JSValue *jsValue = [func callWithArguments:params];
        guard(strcmp(returnValueType, "v")==0) else{
            switch(returnValueType[0] == 'r' ? returnValueType[1] : returnValueType[0]) {
                    WRAP_INVOCATION_ID_RETURN_VALUE(_C_ID, id, toObject);
                    WRAP_INVOCATION_RETURN_VALUE(_C_INT, int, intValue);
                    WRAP_INVOCATION_RETURN_VALUE(_C_SHT, short, shortValue);
                    WRAP_INVOCATION_RETURN_VALUE(_C_USHT, unsigned short, unsignedShortValue);
                    WRAP_INVOCATION_RETURN_VALUE(_C_UINT, unsigned int, unsignedIntValue);
                    WRAP_INVOCATION_RETURN_VALUE(_C_LNG, long, longValue);
                    WRAP_INVOCATION_RETURN_VALUE(_C_ULNG, unsigned long, unsignedLongValue);
                    WRAP_INVOCATION_RETURN_VALUE(_C_LNG_LNG, long long, longLongValue);
                    WRAP_INVOCATION_RETURN_VALUE(_C_ULNG_LNG, unsigned long long, unsignedLongLongValue);
                    WRAP_INVOCATION_RETURN_VALUE(_C_FLT, float, floatValue);
                    WRAP_INVOCATION_RETURN_VALUE(_C_DBL, double, doubleValue);
                    WRAP_INVOCATION_RETURN_VALUE(_C_BOOL, BOOL, boolValue);
                    
            }
        }
    }
}


static NSString *const ForwardInvocationSelectorName = @"__ttpatch_forwardInvocation:";
static void aspect_swizzleForwardInvocation(Class klass) {
    NSCParameterAssert(klass);
    IMP originalImplementation = class_replaceMethod(klass, @selector(forwardInvocation:), (IMP)OC_MSG_SEND_HANDLE, "v@:");
    if (originalImplementation) {
        class_addMethod(klass, NSSelectorFromString(ForwardInvocationSelectorName), originalImplementation, "v@:");
    }

}

static void aspect_prepareClassAndHookSelector(Class cls, SEL selector, BOOL isInstanceMethod) {
    NSCParameterAssert(selector);
    Method targetMethod = isInstanceMethod?class_getInstanceMethod(cls, selector):class_getClassMethod(cls, selector);
    IMP targetMethodIMP = method_getImplementation(targetMethod);
    const char *typeEncoding = method_getTypeEncoding(targetMethod)?:"v@:";
    guard(aspect_isMsgForwardIMP(targetMethodIMP))else{
        
        SEL new_SEL = NSSelectorFromString([NSString stringWithFormat:@"%@%@", TTPatchChangeMethodPrefix, NSStringFromSelector(selector)]);
        class_addMethod(cls, new_SEL, method_getImplementation(targetMethod), typeEncoding);

    }
    class_replaceMethod(cls, selector, aspect_getMsgForwardIMP(cls, selector, isInstanceMethod), typeEncoding);

}


- (void)configJSBrigeActions{
    self[@"log"] = ^(id msg){
        NSLog(@"🍎🍎🍎🍎🍎🍎🍎-------------->%@",msg);
    };
    self[@"MessageQueue_oc_define"] = ^(NSString * interface){
        NSArray * classAndSuper = [interface componentsSeparatedByString:@":"];
        return @{@"self":[classAndSuper firstObject],
                 @"super":[classAndSuper lastObject]
                 };
    };
    
    self[@"MessageQueue_oc_sendMsg"] = ^(id obj,NSString* method,id arguments){
//        __unsafe_unretained id __self = [obj toObject];
//        __unsafe_unretained id params = [arguments toObject];
        __unsafe_unretained id __self = obj;
        __unsafe_unretained id params = arguments;
        return TTPatchUtils.TTPatchDynamicMethodInvocation(__self,TTPatchUtils.TTPatchMethodFormatterToOcFunc(method),params);
        
    };
    
    self[@"MessageQueue_oc_replaceMethod"] = ^(NSString *className,NSString *superClassName,NSString *method,BOOL isInstanceMethod){
//        registerJsMethod(className, superClassName, TTPatchUtils.TTPatchMethodFormatterToOcFunc(method), isInstanceMethod);
        hookClassMethod(className, superClassName, TTPatchUtils.TTPatchMethodFormatterToOcFunc(method), isInstanceMethod);
        
    };
}



-(NSMutableDictionary *)replaceMethodMap{
    return __replaceMethodMap;
}
@end





@implementation TTMethodList_Node


+ (TTMethodList_Node *)createNodeCls:(NSString *)clsName
                          methodName:(NSString *)methodName
                             isClass:(BOOL)isClass{
    TTMethodList_Node * node = [TTMethodList_Node new];
    node.clsName        = clsName;
    node.methodName     = methodName;
    node.key            = [NSString stringWithFormat:@"%@-%@%@",clsName,methodName,isClass?@"+":@"-"];
    node.isClass        = isClass;
    return node;
}

@end

