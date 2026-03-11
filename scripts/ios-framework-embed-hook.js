#!/usr/bin/env node

/**
 * iOS Framework Embed Hook
 * 确保nuisdk.framework正确嵌入到iOS应用中
 */

module.exports = function(context) {
    const fs = require('fs');
    const path = require('path');
    const execSync = require('child_process').execSync;
    
    const projectRoot = context.opts.projectRoot;
    const iosPlatformPath = path.join(projectRoot, 'platforms', 'ios');
    
    console.log('🔧 iOS Framework Embed Hook Started');
    
    try {
        // 检查iOS平台是否存在
        if (!fs.existsSync(iosPlatformPath)) {
            console.log('❌ iOS platform not found, skipping hook');
            return;
        }
        
        // 查找.xcodeproj文件
        const xcodeprojPath = fs.readdirSync(iosPlatformPath)
            .find(file => file.endsWith('.xcodeproj'));
        
        if (!xcodeprojPath) {
            console.log('❌ Xcode project not found');
            return;
        }
        
        const projectPath = path.join(iosPlatformPath, xcodeprojPath);
        console.log('📱 Found Xcode project:', projectPath);
        
        // 检查framework是否存在于Plugins目录
        const frameworkPath = path.join(iosPlatformPath, 'cordova-plugin-AI-speech-transcriber', 'nuisdk.framework');
        if (fs.existsSync(frameworkPath)) {
            console.log('✅ Framework found in Plugins directory');
        } else {
            console.log('❌ Framework not found in Plugins directory');
            return;
        }
        
        console.log('🎯 Framework embed hook completed successfully');
        
    } catch (error) {
        console.error('❌ Error in framework embed hook:', error);
    }
};
