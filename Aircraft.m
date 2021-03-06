classdef Aircraft < handle
    %UNTITLED10 Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        vz=0;
        turnrate;
        pathangle;
        V;
        controller;
        gradientsensor;
        updraftsensor;
        environment;
        name;
    end
    properties (SetAccess=private)
        posx=0
        posy=0
        posz=0
        vx
        vy
        previous_time=0;
        sinkrate
        pHistory
        vHistory
        h_label;
        h_objective;
        h_thermal;
        h_patch;
        h_map;
        landed=0;
    end
    methods
        function obj=Aircraft(posx,posy,posz,V,pathangle,variables,sinkrate,environment,name)
            obj.name=name;
            r=1.0; %Variance of measurement
            obj.controller=FlightController(variables,sinkrate,posx,posy,posz,V,pathangle,@obj.print);
            obj.updraftsensor = Variometer(variables.measurement_noise);
            
            obj.posx=posx;
            obj.posy=posy;
            obj.posz=posz;
            obj.V=V;
            obj.pathangle=pathangle;
            obj.environment=environment;
            obj.sinkrate=sinkrate;
            obj.vx = V*cos(pathangle);
            obj.vy = V*sin(pathangle);
            obj.vz=obj.sinkrate;
            
            obj.pHistory=[posx,posy,posz];
            obj.vHistory=[obj.vx,obj.vy,obj.vz];
        end
        function update(obj,time)
            if obj.posz<0
                % it's landed
                if ~obj.landed
                    obj.print(sprintf('Landed at %4.1f seconds',obj.controller.current_time));
                    obj.landed=1;
                end
                
                return;
            end
            
            %fprintf('deltaT:\n');
            deltaT=time-obj.previous_time;
            %Compute measurements
            [z_R,~]=obj.environment.ExactMeasurement(obj.posx,obj.posy);
            obj.updraftsensor.update(z_R);
            
            measurements=[obj.updraftsensor.estimated_updraft];%
            
            obj.controller.update(measurements,obj.posx,obj.posy,obj.posz,obj.pathangle,obj.V,time);
            %Update history
            obj.pHistory(end+1,:) = [obj.posx,obj.posy,obj.posx];
            obj.vHistory(end+1,:) = [obj.vx,obj.vy,obj.vx];
            %Update state
            obj.posx = obj.posx + deltaT*obj.vx;
            obj.posy = obj.posy + deltaT*obj.vy;
            obj.posz = obj.posz + deltaT*obj.vz;
            
            obj.vx = cos(obj.pathangle)*obj.V;
            obj.vy = sin(obj.pathangle)*obj.V;
            obj.vz = z_R - obj.sinkrate;
            
            obj.pathangle = obj.pathangle + deltaT*obj.controller.turnrate;
            if obj.pathangle > pi
                obj.pathangle=obj.pathangle - 2*pi;
            elseif obj.pathangle < -pi
                obj.pathangle=obj.pathangle + 2*pi;
            end
            
            obj.previous_time = time;
        end
        function Display(obj,axis)
            obj.Clear();
            colours = (obj.vz(1) + 10)/(10--10);
            colours = max(min(colours,1.0),0.0);
            colours=ceil(colours*(length(colormap)-1)+1);
            C=colormap;
            obj.h_patch=Aircraft.display_ac_patch(axis,obj.posx,obj.posy,obj.posz,C(colours,:),obj.pathangle);
            switch obj.controller.sm.state
                case StateMachine.thermalling
                    [obj.h_objective(1),obj.h_objective(2)]=Aircraft.display_objective(axis,obj.controller.est_thermal_pos(1),obj.controller.est_thermal_pos(2),obj.posx,obj.posy,obj.posz,'r:^','r-.');
                    obj.h_thermal = Aircraft.display_thermal_cov(axis,obj.controller.est_thermal_pos(1),obj.controller.est_thermal_pos(2),obj.posz,obj.controller.ekf.P(3,3),obj.controller.ekf.P(4,4));
                case StateMachine.searching
                    [obj.h_objective(1),obj.h_objective(2)]=Aircraft.display_objective(axis,obj.controller.search_centre(1),obj.controller.search_centre(2),obj.posx,obj.posy,obj.posz,'g:^','g-.');
                case StateMachine.cruising
                    [obj.h_objective(1),obj.h_objective(2)]=Aircraft.display_objective(axis,obj.controller.Waypoints(obj.controller.currentWaypoint,1),obj.controller.Waypoints(obj.controller.currentWaypoint,2),obj.posx,obj.posy,obj.posz,'b:^','b-.');
                otherwise
                    fprintf('Error: state %d\n',obj.controller.sm.state);
            end
            
            obj.h_map=Aircraft.display_map(axis,obj.controller.map);
            
            obj.h_label = text(obj.posx+10,obj.posy,obj.posz,sprintf('%s \nHeight %3.1f m \nVertical Velocity: %2.2f',obj.name, obj.posz, obj.vz));
        end
        function print(obj, message)
            fprintf('%s: %s\n',obj.name,message);
        end
        function Clear(obj)
            try
                delete(obj.h_label);
                delete(obj.h_objective);
                delete(obj.h_patch);
                delete(obj.h_map);
                delete(obj.h_thermal);
            catch
            end
        end
        
    end
    methods(Static)
        function [handle1,handle2]=display_objective(axis,x,y,objx,objy,objz,str1,str2)
            handle1=plot3(axis,[x,x],...
                [y,y],...
                [0,objz],str1);
            handle2=plot3(axis,  [objx,x],...
                [objy,y],...
                [objz,objz],str2);
        end
        
        function h = display_ac_patch(axis,xp,yp,zp,c,pathangle)
            ywing=15;
            ystab=3.5;
            yfuse=0.6;
            ytail=0.5;
            xnose=-1.0;
            xwingf=4;
            xwingro=5;
            xwingri=5.5;
            xtailf=10.0;
            xtailr=11.0;
            x=[xnose,xwingf,xwingf,xwingro,xwingri,xtailf,xtailf,xtailr];
            
            y=[0,yfuse,ywing,ywing,yfuse,ytail,ystab,ystab];
            
            x=[x,fliplr(x)];
            y=[y,-fliplr(y)];
            
            x=-x;
            
            f=3/max(y);
            y=y*f;
            x=x*f;
            
            xn = x*cos(pathangle) - y*sin(pathangle);
            yn = y*cos(pathangle) + x*sin(pathangle);
            x=xn;
            y=yn;
            
            axes(axis);
            h=patch(x+xp,y+yp,ones(size(x))*zp,c);
            
        end
        
        function h=display_thermal_cov(axis,x,y,z,px,py)
            th=0:0.1:2*pi;
            xi = sqrt(px) * cos(th);
            yi = sqrt(py) * sin(th);
            xi = xi + x;
            yi = yi + y;
            zi = z*ones(size(xi));
            h = plot3(axis,xi,yi,zi,'r-');
            
        end
        
        function h=display_map(axis,map)
            idx = map.datapoints(:,3)~=0;
            h=plot3(axis,map.datapoints(idx,1),map.datapoints(idx,2),0*map.datapoints(idx,1),'k^');
        end
         
    end
end

