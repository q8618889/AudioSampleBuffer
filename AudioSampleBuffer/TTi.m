//
//  TTi.m
//  CAGradientLayer坐标系统
//
//  Created by ijiayi on 2020/6/11.
//  Copyright © 2020 miaoqu. All rights reserved.
//

#import "TTi.h"

@implementation TTi

- (void)drawRect:(CGRect)rect {
    //获取上下文
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    //1.绘制三角形
    [self drawTriangle:context];
    
    //2.绘制矩形，圆形，椭圆
//    [self drawOther:context];
}

- (void)drawTriangle:(CGContextRef) context {
    //保存context
    CGContextSaveGState(context);
    
    //1.添加绘图路径
//    CGContextMoveToPoint(context, 100, 100);
//    CGContextAddLineToPoint(context, 200, 100);
//    CGContextAddLineToPoint(context, 150, 200);
//    CGContextAddLineToPoint(context, 100, 100);
    CGContextAddEllipseInRect(context, CGRectMake(100, 200, 50, 50));

    //2.设置颜色属性
    //以下定义类似于
//    UIColor *redColor1 = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0];
//    redColor1.CGColor
    CGFloat redColor[4] = {1.0, 0.0, 0.0, 1.0};
    CGFloat greenColor[4] = {0.0, 1.0, 0.0, 1.0};
    
    //3.设置描边颜色，填充颜色
    CGContextSetFillColor(context, greenColor);
    
    //4.绘图
    CGContextDrawPath(context, kCGPathFillStroke);
}

- (void)drawOther:(CGContextRef) context {
     //读取context
//    CGContextRestoreGState(context);
    //添加一个矩形
//    CGContextAddRect(context, CGRectMake(20, 100, 50, 50));
    //添加一个圆形
    CGContextAddEllipseInRect(context, CGRectMake(100, 200, 50, 50));
    //添加一个椭圆
//    CGContextAddEllipseInRect(context, CGRectMake(100, 300, 50, 100));
    
    //绘图
    CGContextDrawPath(context, kCGPathFillStroke);
}


@end
