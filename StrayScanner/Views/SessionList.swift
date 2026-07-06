//
//  SessionList.swift
//  Stray Scanner
//
//  Created by Kenneth Blomqvist on 11/15/20.
//  Copyright © 2020 Stray Robots. All rights reserved.
//

import SwiftUI
import SwiftData

struct SessionList: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var sessions: [Recording]
    @State private var showingInfo = false
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            NavigationStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Recordings")
                            .foregroundColor(Color("TextColor"))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .padding([.top, .leading], 15.0)
                        Spacer()
                        Button(action: {
                            showingSettings.toggle()
                        }, label: {
                            Image(systemName: "gearshape")
                                .resizable()
                                .frame(width: 25, height: 25, alignment: .center)
                                .padding(.top, 17)
                                .padding(.trailing, 10)
                                .foregroundColor(Color("TextColor"))
                        }).sheet(isPresented: $showingSettings) {
                            SettingsView()
                        }
                        Button(action: {
                            showingInfo.toggle()
                        }, label: {
                            Image(systemName: "info.circle")
                                .resizable()
                                .frame(width: 25, height: 25, alignment: .center)
                                .padding(.top, 17)
                                .padding(.trailing, 20)
                                .foregroundColor(Color("TextColor"))
                        }).sheet(isPresented: $showingInfo) {
                            InformationView()
                        }
                    }

                    if !sessions.isEmpty {
                        List {
                            ForEach(sessions) { recording in
                                NavigationLink(destination: SessionDetailView(recording: recording)) {
                                    SessionRow(session: recording)
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                        Spacer()
                    } else {
                        Spacer()
                        Text("No recorded sessions. Record one, and it will appear here.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 50.0)
                    }
                    HStack {
                        Spacer()
                        NavigationLink(destination: NewSessionView(), label: {
                            Text("Record new session")
                                .font(.title3)
                                .padding(20)
                                .background(Color("TextColor"))
                                .foregroundColor(Color("LightColor"))
                                .cornerRadius(35)
                                .padding(20)
                        })
                        Spacer()
                    }
                    if sessions.isEmpty {
                        Spacer()
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .background(Color("BackgroundColor").ignoresSafeArea())
            }
            .background(Color("BackgroundColor").ignoresSafeArea())
        }
    }
}

#Preview {
    SessionList()
        .modelContainer(for: Recording.self, inMemory: true)
}
