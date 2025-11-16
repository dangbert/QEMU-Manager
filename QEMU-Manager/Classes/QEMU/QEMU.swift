/*******************************************************************************
 * Copyright (c) 2021 Jean-David Gadina - www.xs-labs.com
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 ******************************************************************************/

import Foundation
import AppKit

public class QEMU
{
    public class Executable
    {
        @objc public class LaunchFailure: NSObject, Swift.Error
        {
            @objc public private( set ) dynamic var status:  Int
            @objc public private( set ) dynamic var message: String
            
            init( status: Int, message: String )
            {
                self.status  = status
                self.message = message
            }
        }
        
        public private( set ) var name: String
        public private( set ) var url:  URL?
        
        public init( tool: String )
        {
            self.name = tool
            
            if let resources = Bundle.main.resourceURL
            {
                self.url = resources.appendingPathComponent( "qemu" ).appendingPathComponent( "bin" ).appendingPathComponent( tool )
            }
        }
        
        public func execute( arguments: [ String ] ) throws -> ( out: String, err: String )?
        {
            guard let path = self.url?.path else
            {
                throw Error( title: "\( self.name ) not available", message: "The QEMU tool \( self.name ) was not found." )
            }
            
            let out                = Pipe()
            let err                = Pipe()
            let process            = Process()
            process.launchPath     = path
            process.arguments      = arguments
            process.standardOutput = out
            process.standardError  = err
            
            // Log the command being launched
            let commandString = ([ path ] + arguments).map { $0.contains( " " ) ? "\"\( $0 )\"" : $0 }.joined( separator: " " )

            if !arguments.contains( "help" ) {
                DispatchQueue.main.async
                {
                    let alert = NSAlert()
                    alert.messageText = "Launching QEMU"
                    alert.informativeText = "Command:\n\( commandString )"
                    alert.alertStyle = .informational
                    alert.addButton( withTitle: "OK" )
                    alert.runModal()
                }
            }
            
            
            // Set up real-time logging for stdout and stderr (only for VM launches, not help commands)
            let isVMLaunch = !arguments.contains( "help" )
            var outData = Data()
            var errData = Data()
            
            if isVMLaunch
            {
                let outHandle = out.fileHandleForReading
                let errHandle = err.fileHandleForReading
                
                // Set up readability handlers for real-time logging
                outHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty
                    {
                        outData.append( data )
                        if let string = String( data: data, encoding: .utf8 )
                        {
                            // Log each line separately for better readability
                            let lines = string.components( separatedBy: .newlines )
                            for line in lines
                            {
                                let trimmed = line.trimmingCharacters( in: .whitespacesAndNewlines )
                                if !trimmed.isEmpty
                                {
                                    NSLog( "[QEMU stdout] %@", trimmed )
                                }
                            }
                        }
                    }
                }
                
                errHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty
                    {
                        errData.append( data )
                        if let string = String( data: data, encoding: .utf8 )
                        {
                            // Log each line separately for better readability
                            let lines = string.components( separatedBy: .newlines )
                            for line in lines
                            {
                                let trimmed = line.trimmingCharacters( in: .whitespacesAndNewlines )
                                if !trimmed.isEmpty
                                {
                                    NSLog( "[QEMU stderr] %@", trimmed )
                                }
                            }
                        }
                    }
                }
            }
            
            try ObjC.catchException
            {
                process.launch()
                process.waitUntilExit()
            }
            
            // Clean up readability handlers
            if isVMLaunch
            {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
            }
            
            // Read any remaining data
            let dataOut = isVMLaunch ? outData : ( try? out.fileHandleForReading.readToEnd() )
            let dataErr = isVMLaunch ? errData : ( try? err.fileHandleForReading.readToEnd() )
            let strOut  = String( data: dataOut ?? Data(), encoding: .utf8 ) ?? ""
            let strErr  = String( data: dataErr ?? Data(), encoding: .utf8 ) ?? ""
            
            if process.terminationStatus != 0
            {
                throw LaunchFailure( status: Int( process.terminationStatus ), message: strErr )
            }
            
            return ( out: strOut, err: strErr )
        }
    }
    
    public class Img: Executable
    {
        public init()
        {
            super.init( tool: "qemu-img" )
        }
    }
    
    public class System: Executable
    {
        public init( architecture: Config.Architecture )
        {
            super.init( tool: "qemu-system-\( architecture.description )" )
        }
    }
}
